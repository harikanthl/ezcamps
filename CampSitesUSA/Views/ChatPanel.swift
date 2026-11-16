import SwiftUI
import MapKit

/// "Ask ezcamp": a glass panel over the map. Collapsed it's a single ask field; pull it up (or
/// start typing) for the conversation at half height, or all the way up for a long plan. The map
/// stays live behind it and moves to whatever the answer is about.
struct ChatPanel: View {
    @Bindable var engine: ChatEngine
    var onOpenSite: (Site) -> Void
    var onOpenTrip: (Trip) -> Void

    enum Detent: CaseIterable { case bar, half, full }

    @Environment(AISettings.self) private var ai
    @Environment(SiteStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detent: Detent = .bar
    @State private var drag: CGFloat = 0
    @State private var draft = ""
    @FocusState private var typing: Bool

    private static let suggestions = [
        "Free camps near me for tonight",
        "Can I camp here?",
        "What fish can I catch near here?",
        "Plan 3 nights from Denver to Moab, free sites",
    ]

    var body: some View {
        GeometryReader { geo in
            let height = height(for: detent, in: geo.size.height)
            VStack(spacing: 0) {
                handle
                if detent != .bar { conversation.transition(.opacity) }
                inputRow
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(76, height - drag), alignment: .bottom)
            .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .gesture(dragGesture(total: geo.size.height))
        }
        .onChange(of: engine.items.count) { _, n in if n > 0 && detent == .bar { move(to: .half) } }
        #if DEBUG
        .task { if DebugLaunch.flag("debugChatOpen") { try? await Task.sleep(for: .seconds(2)); move(to: .half) } }
        #endif
    }

    // MARK: Pieces

    private var handle: some View {
        Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5)
            .padding(.top, 8).padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .onTapGesture { move(to: detent == .bar ? .half : detent == .half ? .full : .half) }
            .accessibilityLabel(detent == .bar ? "Expand chat" : "Resize chat")
            .accessibilityAddTraits(.isButton)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if engine.items.isEmpty { empty }
                    ForEach(engine.items) { item in row(item).id(item.id) }
                    if engine.running && engine.items.last?.kind != .assistant {
                        ProgressView().padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.items.last?.text) {
                if let id = engine.items.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AppLogo(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask ezcamp").font(.headline)
                    Text(modelLine).font(.caption).foregroundStyle(.secondary)
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.dusk.opacity(0.12), in: .capsule)
                            .foregroundStyle(Color.dusk)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(.top, 4)
    }

    private var modelLine: String {
        let m = ai.model(for: .chat)
        return m.isOnDevice ? "On this iPhone · answers from ezcamp's data" : "\(m.provider?.shortTitle ?? "") · \(m.label)"
    }

    @ViewBuilder private func row(_ item: ChatItem) -> some View {
        switch item.kind {
        case .user:
            Text(item.text)
                .font(.body)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.dusk, in: .rect(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .activity:
            Label(item.text, systemImage: "magnifyingglass")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case .error:
            Label(item.text, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.berry)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown(item.text)).font(.body).textSelection(.enabled)
                if !item.siteIDs.isEmpty { siteChips(item.siteIDs) }
                if item.tripCreated, let trip = engine.lastTrip {
                    Button { onOpenTrip(trip) } label: {
                        Label("Open \(trip.name)", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent).tint(.dusk)
                }
            }
            .padding(.trailing, 20)
        }
    }

    private func siteChips(_ ids: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ids.compactMap { store.site(id: $0) }) { s in
                    Button { onOpenSite(s) } label: {
                        HStack(spacing: 6) {
                            Icon3D(s.kind.icon3D, size: 18)
                            Text(s.name).lineLimit(1)
                            Text(s.priceLabel).foregroundStyle(s.likelyFree ? Color.meadow : .secondary)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.background.opacity(0.7), in: .capsule)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Color.dusk)
            TextField("Ask ezcamp…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                // Expand only on a real tap or typing, never because the field got focus on its own.
                .simultaneousGesture(TapGesture().onEnded { if detent == .bar { move(to: .half) } })
                .onChange(of: draft) { _, text in if !text.isEmpty && detent == .bar { move(to: .half) } }
            if engine.running {
                Button { engine.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                    .tint(.berry).accessibilityLabel("Stop")
            } else if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .tint(.dusk).accessibilityLabel("Send")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if !engine.items.isEmpty {
                Button { engine.clear() } label: { Image(systemName: "square.and.pencil").font(.title3) }
                    .tint(.secondary)
                    .accessibilityLabel("New conversation")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: draft.isEmpty)
    }

    // MARK: Behaviour

    private func send(_ text: String) {
        engine.send(text, settings: ai)
        draft = ""
    }

    private func height(for d: Detent, in total: CGFloat) -> CGFloat {
        switch d {
        case .bar: 76
        case .half: total * 0.48
        case .full: total * 0.9
        }
    }

    private func move(to d: Detent) {
        if reduceMotion { withAnimation(.easeOut(duration: 0.2)) { detent = d } }
        else { withAnimation(.spring(duration: 0.4, bounce: 0.12)) { detent = d } }
    }

    /// Follows the finger, then settles on the detent nearest where a flick would have landed.
    private func dragGesture(total: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                let base = height(for: detent, in: total)
                let proposed = base - v.translation.height
                // Rubber-band past the ends instead of a hard stop.
                let lo = height(for: .bar, in: total), hi = height(for: .full, in: total)
                let clamped = proposed < lo ? lo - (lo - proposed) * 0.2 : proposed > hi ? hi + (proposed - hi) * 0.2 : proposed
                drag = base - clamped
            }
            .onEnded { v in
                let base = height(for: detent, in: total)
                let landing = base - v.predictedEndTranslation.height
                let target = Detent.allCases.min { abs(height(for: $0, in: total) - landing) < abs(height(for: $1, in: total) - landing) } ?? detent
                if target == .bar { typing = false }
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.2)) { detent = target; drag = 0 }
                } else {
                    withAnimation(.spring(duration: 0.4, bounce: 0.12)) { detent = target; drag = 0 }
                }
            }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
