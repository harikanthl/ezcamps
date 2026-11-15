import SwiftUI
import MapKit

/// A long-press point on the map, waiting for its land check.
struct LandQuery: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// Sheet answering "Can I camp here?" for a long-pressed point.
struct LandCheckView: View {
    let query: LandQuery
    @State private var result: LandCheck?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Can I camp here?").font(.title2.weight(.bold))

                if let result {
                    answer(result)
                } else if failed {
                    Label("Couldn't reach the land records service. Check your connection and try again.",
                          systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderedProminent).tint(.sunset)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking who manages this land…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                }

                Text("\(query.coordinate.latitude, specifier: "%.5f"), \(query.coordinate.longitude, specifier: "%.5f")")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Land manager from the BLM Surface Management Agency map. Always check posted signs, closures and fire restrictions.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .task { await load() }
        .sensoryFeedback(.success, trigger: result?.verdict == .likelyYes)
    }

    private func answer(_ r: LandCheck) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: r.verdict.symbol)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(r.verdict.color, in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.verdict.label).font(.headline).foregroundStyle(r.verdict.color)
                    Text(r.unitName.map { "\(r.agencyName) · \($0)" } ?? r.agencyName)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text(r.summary)
            if !r.rules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(r.rules, id: \.self) { rule in
                        Label(rule, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary, r.verdict.color)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(r.verdict.color.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
        .transition(.opacity.combined(with: .scale(0.98, anchor: .top)))
    }

    private func load() async {
        failed = false
        do {
            let r = try await LandCheck.lookup(query.coordinate)
            withAnimation(.easeOut(duration: 0.2)) { result = r }
        } catch {
            failed = true
        }
    }
}

extension LandCheck.Verdict {
    var label: String {
        switch self {
        case .likelyYes: "Likely yes"
        case .check: "Check local rules"
        case .likelyNo: "Likely no"
        }
    }
    var symbol: String {
        switch self {
        case .likelyYes: "checkmark"
        case .check: "questionmark"
        case .likelyNo: "xmark"
        }
    }
    var color: Color {
        switch self {
        case .likelyYes: .meadow
        case .check: .canyon
        case .likelyNo: .berry
        }
    }
}

/// Key for the public-lands overlay. Swatches match the BLM SMA map's colors.
struct PublicLandsLegend: View {
    private let items: [(String, Color)] = [
        ("BLM", Color(hex: 0xFEE67A)), ("Forest Service", Color(hex: 0xC2E3B4)),
        ("Park Service", Color(hex: 0xCDB8DD)), ("State", Color(hex: 0xA9D3F0)),
        ("Tribal", Color(hex: 0xFDB46C)), ("Wildlife refuge", Color(hex: 0x86CDB0)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.0) { name, color in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 14)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.15)))
                            Text(name)
                        }
                    }
                }
            }
            Label("Long-press anywhere to ask “Can I camp here?”", systemImage: "hand.point.up.left.fill")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
    }
}
