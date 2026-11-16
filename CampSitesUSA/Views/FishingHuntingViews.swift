import SwiftUI
import MapKit

/// "Fishing & hunting" on the site card: fish and game recorded nearby, live river flow, the
/// state's license rules with links, and lodges, outfitters and bait shops nearby. Every part says
/// where it came from; records show what people saw, not a promise of what you'll catch.
struct FishingHuntingSection: View {
    let site: Site

    @State private var wildlife: NearbyWildlife?
    @State private var wildlifeFailed = false
    @State private var gauges: [StreamGauge]?
    @State private var outfitters: [OutfitterPlace]?
    @State private var showAllFish = false

    private var rules: StateLicenses? { LicenseBook.state(site.state) }
    private var federal: StateLicenses? { LicenseBook.state("US") }
    /// Hunting is closed in most national parks; say so up front rather than list deer to shoot.
    private var inNationalPark: Bool { site.source == .nps || (site.agency ?? "").localizedCaseInsensitiveContains("National Park") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Fishing & hunting", icon: "fishing")
            fishBlock
            if let gauges, !gauges.isEmpty { flowBlock(gauges) }
            gameBlock
            licenseBlock
            outfittersBlock
            Text("Species: iNaturalist research-grade sightings within 25 km, not a guarantee of a catch. Flow: USGS, live. Rules: \(rules?.agency ?? "the state wildlife agency"). Always read the current regulations.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: site.id) { await load() }
    }

    // MARK: Fish

    @ViewBuilder private var fishBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text("Fish recorded nearby").font(.subheadline.weight(.semibold)) } icon: { Icon3D("fish", size: 20) }
            if let w = wildlife {
                let game = w.gameFish
                if w.fish.isEmpty {
                    Text("No fish sightings recorded within 25 km.").font(.caption).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(showAllFish ? w.fish : (game.isEmpty ? Array(w.fish.prefix(6)) : game)) { f in
                            speciesChip(f, tint: f.game == true ? .sky : .secondary)
                        }
                    }
                    if !showAllFish && !game.isEmpty && w.otherFish.count > 0 {
                        Button("+ \(w.otherFish.count) other fish recorded") {
                            withAnimation(.easeOut(duration: 0.2)) { showAllFish = true }
                        }
                        .font(.caption.weight(.semibold)).tint(.sky)
                    }
                    if w.fish.contains(where: \.protected) {
                        Label("At-risk species are marked. Rules vary: many must be released.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Color.canyon)
                    }
                }
            } else if wildlifeFailed {
                Text("Couldn't load wildlife records right now.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Checking what's been caught and seen nearby…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func speciesChip(_ s: NearbySpecies, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(s.name).fontWeight(.semibold)
            if s.protected { Text("At-risk").font(.caption2.weight(.bold)).foregroundStyle(Color.canyon) }
            Text("\(s.observations)×").foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(tint == .secondary ? Color.primary : tint)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background((s.protected ? Color.canyon : tint == .secondary ? Color.gray : tint).opacity(0.12), in: .capsule)
        .accessibilityLabel("\(s.name), \(s.observations) sightings\(s.protected ? ", at-risk species" : "")")
    }

    // MARK: River flow

    private func flowBlock(_ gauges: [StreamGauge]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text("River flow now").font(.subheadline.weight(.semibold)) } icon: { Icon3D("wave", size: 20) }
            ForEach(gauges.prefix(3)) { g in
                HStack(alignment: .firstTextBaseline) {
                    Text(g.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text("\(g.cfs.formatted(.number.precision(.fractionLength(0)))) cfs · \(g.miles.formatted(.number.precision(.fractionLength(0)))) mi")
                        .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.sky)
                }
            }
        }
    }

    // MARK: Game

    @ViewBuilder private var gameBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text("Game seen nearby").font(.subheadline.weight(.semibold)) } icon: { Icon3D("deer", size: 20) }
            if inNationalPark {
                Label("Hunting isn't allowed in most national parks. Check the park's rules.", systemImage: "nosign")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.berry)
            }
            if let w = wildlife {
                if w.game.isEmpty {
                    Text("No game sightings recorded within 25 km.").font(.caption).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(w.game.prefix(10)) { g in
                            HStack(spacing: 4) {
                                Icon3D(g.kind == "bird" ? "duck" : "deer", size: 14)
                                Text(g.name).fontWeight(.semibold)
                                if g.protected { Text("At-risk").font(.caption2.weight(.bold)).foregroundStyle(Color.canyon) }
                                Text("\(g.observations)×").foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background((g.protected ? Color.canyon : Color.meadow).opacity(0.12), in: .capsule)
                        }
                    }
                }
            }
        }
    }

    // MARK: Licenses

    @ViewBuilder private var licenseBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text("Licenses in \(stateName)").font(.subheadline.weight(.semibold)) } icon: { Icon3D("shield", size: 20) }
            if let r = rules {
                if let f = r.fishing {
                    ruleRow("Fishing", detail: f.licenseRequiredFromAge.map { "License needed from age \($0)" } ?? f.fishingNote ?? "License required",
                            extra: f.freeFishingDays.map { "Free fishing days: \($0)" }, buy: f.licenseUrl, regs: f.regulationsUrl)
                }
                if let h = r.hunting, !inNationalPark {
                    ruleRow("Hunting", detail: h.hunterEducation ?? "License required",
                            extra: h.blazeOrange.map { "Hunter orange: \($0)" }, buy: h.licenseUrl, regs: h.regulationsUrl)
                }
                if !inNationalPark, let duck = federal?.hunting?.hunterEducation {
                    Text("Waterfowl: \(duck)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Check \(stateName)'s wildlife agency for license rules before you fish or hunt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var stateName: String { OfflineStoreNames.name(site.state) }

    private func ruleRow(_ title: String, detail: String, extra: String?, buy: String?, regs: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.bold))
                Text(detail).font(.caption)
            }
            if let extra { Text(extra).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 14) {
                if let url = URL.web(buy) { Link("Buy a license", destination: url) }
                if let url = URL.web(regs) { Link("Regulations", destination: url) }
            }
            .font(.caption.weight(.semibold))
            .tint(.sunset)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12, style: .continuous))
    }

    // MARK: Lodges and outfitters

    @ViewBuilder private var outfittersBlock: some View {
        if let outfitters, !outfitters.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lodges, guides and bait shops").font(.subheadline.weight(.semibold))
                ForEach(outfitters.prefix(5)) { o in
                    Button { o.item.openInMaps() } label: {
                        HStack(spacing: 8) {
                            Icon3D(o.kind.icon, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.name).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                                Text("\(o.kind.label) · \(o.miles.formatted(.number.precision(.fractionLength(o.miles < 10 ? 1 : 0)))) mi")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens in Maps")
                }
            }
        }
    }

    // MARK: Loading

    private func load() async {
        async let w = try? await RatingsAPI.wildlife(near: site.coordinate)
        async let g = StreamFlow.gauges(near: site.coordinate)
        async let o = OutfitterFinder.nearby(site.coordinate)
        let (wl, gs, os) = await (w, g, o)
        guard !Task.isCancelled else { return }
        if let wl { wildlife = wl } else { wildlifeFailed = true }
        gauges = gs
        outfitters = os
    }
}

// MARK: - Lodges, outfitters, bait and tackle (Apple Maps, live)

struct OutfitterPlace: Identifiable {
    enum Kind {
        case lodge, outfitter, tackle
        var label: String {
            switch self {
            case .lodge: "Hunting or fishing lodge"
            case .outfitter: "Outfitter or guide"
            case .tackle: "Bait and tackle"
            }
        }
        var icon: String {
            switch self {
            case .lodge: "camping"
            case .outfitter: "deer"
            case .tackle: "fishing"
            }
        }
    }
    let id = UUID()
    let kind: Kind
    let name: String
    let miles: Double
    let item: MKMapItem
}

enum OutfitterFinder {
    /// Nearest few of each within 40 miles, by distance. Names are checked so a text match on
    /// "lodge" doesn't return a motel chain.
    static func nearby(_ c: CLLocationCoordinate2D) async -> [OutfitterPlace] {
        let searches: [(String, OutfitterPlace.Kind, [String])] = [
            ("hunting lodge", .lodge, ["hunt", "lodge", "ranch", "outfit"]),
            ("fishing lodge", .lodge, ["fish", "lodge", "angl", "fly"]),
            ("hunting outfitter guide", .outfitter, ["outfit", "guide", "hunt", "fly", "angl"]),
            ("bait and tackle", .tackle, ["bait", "tackle", "fly", "angl", "sport", "outdoor", "fish"]),
        ]
        var out: [OutfitterPlace] = []
        var seen = Set<String>()
        for (query, kind, words) in searches {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            let meters = 80 * TripPlanner.metersPerMile
            req.region = MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters)
            req.resultTypes = .pointOfInterest
            guard let items = try? await MKLocalSearch(request: req).start().mapItems else { continue }
            for item in items {
                let name = item.name ?? ""
                let lower = name.lowercased()
                let d = TripPlanner.miles(c, item.location.coordinate)
                guard d <= 40, words.contains(where: lower.contains), seen.insert(lower).inserted else { continue }
                out.append(OutfitterPlace(kind: kind, name: name, miles: d, item: item))
            }
        }
        return out.sorted { $0.miles < $1.miles }
    }
}

/// State names for display ("UT" → "Utah"), from the bundled state bounds.
enum OfflineStoreNames {
    private static let names: [String: String] = {
        guard let url = Bundle.main.url(forResource: "state_bounds", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([StateBounds].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.code, $0.name) }, uniquingKeysWith: { a, _ in a })
    }()

    static func name(_ code: String) -> String { names[code] ?? code }
}
