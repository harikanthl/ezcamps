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
    @State private var road: ForestRoad?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Can I camp here?").font(.title2.weight(.bold))

                if let result {
                    answer(result)
                } else if failed {
                    Label(FeatureFlags.offlinePacks
                          ? "No signal, and this area isn't downloaded. Save the state in Offline maps (Saved tab) before you lose signal."
                          : "Couldn't reach the land records service. Check your connection and try again.",
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
                    // The unit is often just the agency's name again ("Bureau of Land Management"); don't repeat it.
                    Text(r.unitName.flatMap { $0.caseInsensitiveCompare(r.agencyName) == .orderedSame ? nil : "\(r.agencyName) · \($0)" }
                         ?? r.agencyName)
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text(r.summary)
            if let road { RoadCard(road: road) }
            if r.offline {
                Label("Offline answer from your downloaded map. Less precise near boundaries.", systemImage: "arrow.down.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.sky)
            }
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
            // National forest: which forest road is nearest, and who may drive it when (MVUM).
            if r.agencyCode == "USFS", let found = await ForestRoad.nearest(to: query.coordinate) {
                withAnimation(.easeOut(duration: 0.2)) { road = found }
            }
        } catch {
            // No signal: answer from the downloaded public-lands map if this area is saved.
            if let code = OfflineLand.agency(at: query.coordinate) {
                var r = LandCheck.make(code: code, unit: nil, at: query.coordinate)
                r.offline = true
                withAnimation(.easeOut(duration: 0.2)) { result = r }
            } else {
                failed = true
            }
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

/// Nearest forest road from the Motor Vehicle Use Map.
private struct RoadCard: View {
    let road: ForestRoad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(road.title, systemImage: road.isTrail ? "point.topleft.down.to.point.bottomright.curvepath" : "road.lanes")
                .font(.subheadline.weight(.semibold))
            Text(road.access.replacingOccurrences(of: "Vehicles", with: "vehicles"))
                .font(.subheadline)
            if let d = road.datesOpen { Label("Open \(d.replacingOccurrences(of: "-", with: " – "))", systemImage: "calendar").font(.caption) }
            if let s = road.surface { Label(s, systemImage: "car.side").font(.caption) }
            if let district = road.district { Text(district).font(.caption).foregroundStyle(.secondary) }
            Text("Many forests allow camping within a set distance of open roads (often 150–300 ft). Check this forest's MVUM legend for the exact rule.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.meadow.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// Key for the forest roads layer, using the Forest Service's own MVUM swatches.
struct ForestRoadsLegend: View {
    let zoomedIn: Bool

    private let items: [(String, String)] = [
        ("mvum_road_all_yearlong", "All vehicles"),
        ("mvum_road_legal_yearlong", "Highway-legal only"),
        ("mvum_road_all_seasonal", "Seasonal"),
        ("mvum_trail_atv", "ATV trail (≤50 in)"),
        ("mvum_trail_motorcycle", "Motorcycle trail"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if zoomedIn {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.0) { file, label in
                            HStack(spacing: 5) {
                                if let img = UIImage(named: file) {
                                    Image(uiImage: img).interpolation(.none).resizable().frame(width: 16, height: 16)
                                }
                                Text(label)
                            }
                        }
                    }
                }
                Label("Long-press a forest road for its dates and vehicle rules", systemImage: "hand.point.up.left.fill")
                    .foregroundStyle(.secondary)
            } else {
                Label("Zoom in to see forest roads (Motor Vehicle Use Map)", systemImage: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
    }
}
