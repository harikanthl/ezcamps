import SwiftUI
import SwiftData
import CoreLocation

/// "Plan with AI": describe the trip in your own words. The model only reads the request; ezcamp's
/// planner builds the route and picks real campsites. You confirm what it understood before planning.
struct PlanWithAIView: View {
    var onCreate: (Trip) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SiteStore.self) private var store
    @Environment(LocationProvider.self) private var location
    @Environment(AISettings.self) private var ai

    @State private var text = ""
    @State private var intent: TripIntent?
    @State private var readByModel = true
    @State private var phase: Phase = .idle
    @State private var error: String?
    /// The running read or plan. Cancel stops it, so a plan can't finish after the sheet is gone.
    @State private var work: Task<Void, Never>?
    @FocusState private var focused: Bool

    enum Phase { case idle, understanding, planning }

    private static let examples = [
        "SF to Moab via Zion, 5 nights, free sites, under 3 hours of driving a day",
        "Denver to Glacier next Friday, 250 miles a day, free camping",
        "Weekend from Seattle to the Olympic Peninsula",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            AppLogo(size: 40)
                            Text("Where do you want to go?").font(.title3.weight(.bold))
                        }
                        TextField("Describe your trip…", text: $text, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($focused)
                            .padding(12)
                            .background(Color.dusk.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
                        if text.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Self.examples, id: \.self) { ex in
                                    Button {
                                        text = ex
                                    } label: {
                                        Label(ex, systemImage: "text.bubble")
                                            .font(.subheadline)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.pressable)
                                    .foregroundStyle(Color.dusk)
                                }
                            }
                        }
                    }

                    modelRow

                    if let intent { IntentCard(intent: intent, readByModel: readByModel) }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(Color.berry)
                    }
                }
                .padding()
            }
            .navigationTitle("Plan with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } } }
            .safeAreaInset(edge: .bottom) { actionButton }
            .onAppear {
                if phase == .idle && intent == nil { focused = true }
                #if DEBUG
                // Testing aid: `-debugAIPrompt "…"` fills the request and runs it, once per launch.
                // (onAppear also fires coming back from Settings, and on every new sheet.)
                if text.isEmpty, let p = DebugLaunch.string("debugAIPrompt") {
                    text = p
                    let autoPlan = DebugLaunch.flag("debugAIAutoPlan")
                    start(.understanding) {
                        await understand()
                        if autoPlan, !Task.isCancelled, intent?.isUsable == true {
                            phase = .planning
                            await plan()
                        }
                    }
                }
                #endif
            }
            .onChange(of: text) { if intent != nil && phase == .idle { intent = nil } }
        }
        .interactiveDismissDisabled(phase != .idle)
    }

    private var modelRow: some View {
        let choice = ai.model(for: .planTrip)
        return HStack(spacing: 8) {
            Image(systemName: choice.isOnDevice ? "iphone" : "cloud")
            Text(choice.isOnDevice ? "On this iPhone (private)" : "\(choice.provider?.shortTitle ?? "") · \(choice.modelID)")
                .lineLimit(1)
            Spacer()
            NavigationLink("Change") { SettingsView() }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actionButton: some View {
        Button {
            if intent == nil { start(.understanding) { await understand() } } else { start(.planning) { await plan() } }
        } label: {
            HStack(spacing: 8) {
                switch phase {
                case .understanding: ProgressView().tint(.white); Text("Reading your request…")
                case .planning: ProgressView().tint(.white); Text("Finding camps along the way…")
                case .idle:
                    Image(systemName: intent == nil ? "sparkles" : "map.fill")
                    Text(intent == nil ? "Understand my trip" : "Looks right, plan it")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(canAct ? AnyShapeStyle(Color.dusk) : AnyShapeStyle(Color.secondary.opacity(0.4)),
                        in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!canAct)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var canAct: Bool {
        phase == .idle && !text.trimmingCharacters(in: .whitespaces).isEmpty && (intent == nil || intent!.isUsable)
    }

    /// Starts `body` as the one running job. The phase flips synchronously, so a quick second tap
    /// finds the button disabled instead of starting a second plan (and a duplicate trip).
    private func start(_ next: Phase, _ body: @escaping @MainActor () async -> Void) {
        guard phase == .idle else { return }
        phase = next
        work = Task {
            await body()
            phase = .idle
            work = nil
        }
    }

    private func cancel() {
        work?.cancel()
        work = nil
        phase = .idle
        dismiss()
    }

    private func understand() async {
        focused = false
        error = nil
        let request = text
        do {
            let (result, byModel) = try await TripAI.understand(request, using: ai.model(for: .planTrip), settings: ai)
            // Cancelled, or the request was edited while the model was reading it: drop the stale answer.
            guard !Task.isCancelled, request == text else { return }
            readByModel = byModel
            withAnimation(.easeOut(duration: 0.2)) { intent = result }
            if !result.isUsable { error = "Where are you headed? Add a destination and try again." }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func plan() async {
        guard let intent, let toName = intent.to else { return }
        error = nil
        do {
            let here = location.location?.coordinate
            let start: TripPlace
            if let fromName = intent.from {
                guard let p = await TripPlanner.place(named: fromName, near: here) else { throw TripPlanner.PlanError.notFound(fromName) }
                start = p
            } else {
                guard let here else { throw TripPlanner.PlanError.noStart }
                start = TripPlace(name: "My location", coordinate: here)
            }
            guard let end = await TripPlanner.place(named: toName, near: start.coordinate) else {
                throw TripPlanner.PlanError.notFound(toName)
            }
            var via: [TripPlace] = []
            for name in intent.via {
                guard let p = await TripPlanner.place(named: name, near: start.coordinate) else { throw TripPlanner.PlanError.notFound(name) }
                via.append(p)
            }
            let trip = try await TripPlanner.makeTrip(
                from: start, to: end, via: via, startDate: intent.start ?? .now, dailyMiles: intent.dailyMiles,
                preferFree: intent.freeOnly ?? true, totalNights: intent.nights, store: store, context: context)
            dismiss()
            onCreate(trip)
        } catch is CancellationError {
            // Cancelled: nothing was saved.
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

/// What the model understood, so the person can check it before anything is planned.
private struct IntentCard: View {
    let intent: TripIntent
    let readByModel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Here's what I understood", systemImage: "checkmark.bubble.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.dusk)
            row("location.fill", .meadow, "From", intent.from ?? "My location")
            ForEach(Array(intent.via.enumerated()), id: \.offset) { _, v in row("mappin", .sunset, "Via", v) }
            row("flag.checkered", .berry, "To", intent.to ?? "Missing")
            if let d = intent.start { row("calendar", .sky, "Start", d.formatted(.dateTime.weekday(.wide).month().day())) }
            if let n = intent.nights { row("moon.stars.fill", .dusk, "Nights", "\(n)") }
            row("car.fill", .canyon, "Driving", "Up to \(intent.dailyMiles) mi a day"
                + (intent.maxDrivingHours.map { " (~\($0.formatted(.number.precision(.fractionLength(0...1)))) h)" } ?? ""))
            row("dollarsign.circle.fill", .meadow, "Camps", (intent.freeOnly ?? true) ? "Free first" : "Any")
            if !readByModel {
                Label("Read without AI: Apple's on-device model isn't available on this iPhone. Add a key in Settings for smarter reading.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(Color.canyon)
            }
            Text("Not right? Edit your request above. Camps come from ezcamp's data, not the AI.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.dusk.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    private func row(_ symbol: String, _ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 20)
            Text(label).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Text(value).fontWeight(.semibold).lineLimit(2)
        }
        .font(.subheadline)
    }
}
