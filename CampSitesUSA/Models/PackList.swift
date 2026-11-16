import Foundation

// A pack list for a stay or a trip: water, food, gear and bear storage, worked out from what the
// person plans to do, how many nights and people, the forecast lows, and the site itself. Every
// line comes from packing.json, which cites a public source for each recommendation (NPS, CDC,
// Ready.gov, the Academy of Nutrition and Dietetics, NOLS, REI, hunter education), and the app
// shows that source next to the line.

enum PackActivity: String, CaseIterable, Identifiable, Codable {
    case camping, dayHiking, backpacking, mountainBiking, trailRunning, fishing, hunting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camping: "Camping"
        case .dayHiking: "Day hiking"
        case .backpacking: "Backpacking"
        case .mountainBiking: "Mountain biking"
        case .trailRunning: "Trail running"
        case .fishing: "Fishing"
        case .hunting: "Hunting"
        }
    }

    var icon3D: String {
        switch self {
        case .camping: "tent"
        case .dayHiking, .backpacking: "boot"
        case .mountainBiking: "bicycle"
        case .trailRunning: "boot"
        case .fishing: "fishing"
        case .hunting: "deer"
        }
    }

    /// Hours on the move per day, for water and energy (a typical day, adjustable later).
    var activeHours: Double {
        switch self {
        case .camping, .fishing: 0
        case .dayHiking: 4
        case .backpacking: 6
        case .mountainBiking: 3
        case .trailRunning: 1.5
        case .hunting: 6
        }
    }

    /// Favorites from Settings ("What do you like to do?").
    static func favorites() -> Set<PackActivity> {
        let raw = UserDefaults.standard.string(forKey: "packActivities") ?? "camping,dayHiking"
        return Set(raw.split(separator: ",").compactMap { PackActivity(rawValue: String($0)) })
    }

    static func saveFavorites(_ set: Set<PackActivity>) {
        UserDefaults.standard.set(set.map(\.rawValue).sorted().joined(separator: ","), forKey: "packActivities")
    }
}

struct PackItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String?
    let source: String?
}

struct PackSection: Identifiable {
    let id: String
    let title: String
    let icon: String
    var summary: String?
    var items: [PackItem]
}

struct PackInputs {
    var activities: Set<PackActivity>
    var nights: Int
    var people: Int
    /// Coldest overnight low expected, °F (nil when there's no forecast).
    var coldestLow: Int?
    /// Warmest overnight low; a warm night means a hot day.
    var warmestLow: Int?
    /// The site lists drinking water.
    var siteHasWater: Bool
    /// Black or grizzly bears have been recorded near the site.
    var bearCountry: Bool
}

enum PackPlanner {
    /// packing.json, loaded once. Loose parsing: the guide's sections have different shapes.
    private static let guide: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "packing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }()

    private static func dict(_ o: Any?) -> [String: Any] { o as? [String: Any] ?? [:] }
    private static func list(_ o: Any?) -> [[String: Any]] { o as? [[String: Any]] ?? [] }
    private static func source(_ o: [String: Any]) -> String? {
        (o["source"] as? String) ?? (o["sources"] as? [String])?.first
    }

    /// Liters for the whole group and stay: ~1 gal per person per day at camp (Ready.gov) plus
    /// ~0.5 L per active hour (doubled on hot days).
    static func waterLiters(_ input: PackInputs) -> Double {
        let acts = input.activities.isEmpty ? [.camping] : input.activities
        let hot = (input.warmestLow ?? 0) >= 65
        let active = acts.map(\.activeHours).max() ?? 0
        return (3.8 + active * 0.5 * (hot ? 2 : 1)) * Double(max(1, input.nights + 1) * max(1, input.people))
    }

    static func make(_ input: PackInputs) -> [PackSection] {
        let acts = input.activities.isEmpty ? [.camping] : input.activities
        let days = max(1, input.nights + 1)
        let people = max(1, input.people)
        let cold = (input.coldestLow ?? 99) <= 32
        let hot = (input.warmestLow ?? 0) >= 65
        var sections: [PackSection] = []

        // Water: camp needs per person per day, plus about 0.5 L per active hour.
        let active = acts.map(\.activeHours).max() ?? 0
        let liters = waterLiters(input)
        var water: [PackItem] = []
        let hydration = dict(guide["hydration"])
        if let camp = dict(dict(hydration["byActivity"])["camping"])["perDay"] as? String {
            water.append(PackItem(id: "w-base", title: "About 1 gallon per person per day at camp", detail: camp,
                                  source: source(dict(dict(hydration["byActivity"])["camping"]))))
        }
        if active > 0, let base = list(hydration["baseline"]).first(where: { ($0["context"] as? String ?? "").contains("Moderate") }) {
            water.append(PackItem(id: "w-active", title: "About 0.5 L for every hour on the move", detail: base["guidance"] as? String, source: source(base)))
        }
        if hot, let heat = list(dict(hydration["adjustments"])["heat"]).first {
            water.append(PackItem(id: "w-heat", title: "Hot days: drink more, and eat salty snacks", detail: heat["guidance"] as? String, source: source(heat)))
        }
        if cold, let c = list(dict(hydration["adjustments"])["cold"]).first {
            water.append(PackItem(id: "w-cold", title: "Cold nights: insulated bottles and warm drinks", detail: c["guidance"] as? String, source: source(c)))
        }
        if active >= 1, let e = list(hydration["electrolytes"]).first {
            water.append(PackItem(id: "w-salt", title: "Electrolytes for efforts over an hour", detail: e["guidance"] as? String, source: source(e)))
        }
        if !input.siteHasWater {
            for t in list(hydration["waterTreatment"]).prefix(3) {
                water.append(PackItem(id: "w-treat-\(t["method"] as? String ?? "")", title: "Treat natural water: \((t["method"] as? String ?? "").lowercased())",
                                      detail: t["guidance"] as? String, source: source(t)))
            }
        }
        sections.append(PackSection(
            id: "water", title: "Water", icon: "droplet",
            summary: "Carry or plan for about \(Int(liters.rounded())) L (\(Int((liters / 3.785).rounded())) gal) for \(people) \(people == 1 ? "person" : "people"), \(days) \(days == 1 ? "day" : "days")."
                + (input.siteHasWater ? " This site lists drinking water." : " No drinking water is listed here: bring it all, or treat what you find."),
            items: water))

        // Food: meals and snacks for each activity, merged without repeats.
        let foods = dict(dict(guide["foods"])["byActivity"])
        var seen = Set<String>()
        var meals: [PackItem] = [], snacks: [PackItem] = []
        for a in PackActivity.allCases where acts.contains(a) {
            let f = dict(foods[a.rawValue])
            for m in list(f["meals"]) where seen.insert(m["item"] as? String ?? "").inserted {
                meals.append(PackItem(id: "m-\(meals.count)-\(a.rawValue)", title: m["item"] as? String ?? "", detail: m["why"] as? String, source: source(m)))
            }
            for s in list(f["snacks"]) where seen.insert(s["item"] as? String ?? "").inserted {
                snacks.append(PackItem(id: "s-\(snacks.count)-\(a.rawValue)", title: s["item"] as? String ?? "", detail: s["why"] as? String, source: source(s)))
            }
        }
        var energy: [PackItem] = []
        let energyBy = dict(dict(guide["energy"])["byActivity"])
        for a in PackActivity.allCases where acts.contains(a) && a != .camping {
            let key = a == .hunting ? "huntingOrCampingInCold" : a.rawValue
            let e = dict(energyBy[key])
            if let g = e["guidance"] as? String, e["verification"] as? String != "unsourced" {
                energy.append(PackItem(id: "e-\(a.rawValue)", title: "\(a.label): energy", detail: g, source: source(e)))
            }
        }
        if cold, let c = list(dict(guide["energy"])["coldRaisesNeeds"]).first {
            energy.append(PackItem(id: "e-cold", title: "Cold raises how much you need to eat", detail: c["guidance"] as? String, source: source(c)))
        }
        if let safety = list(dict(guide["foods"])["foodSafety"]).first {
            energy.append(PackItem(id: "e-safe", title: "Keep the cooler below 40°F", detail: safety["guidance"] as? String, source: source(safety)))
        }
        sections.append(PackSection(id: "meals", title: "Meals", icon: "forkknife", items: Array(meals.prefix(8))))
        sections.append(PackSection(id: "snacks", title: "Snacks", icon: "sparkles", items: Array(snacks.prefix(10))))
        if !energy.isEmpty { sections.append(PackSection(id: "energy", title: "How much to eat", icon: "fire", items: energy)) }

        // Gear: activity-specific first, then the Ten Essentials for anyone leaving camp.
        let gearBy = dict(guide["activityGear"])
        var gear: [PackItem] = []
        var gearSeen = Set<String>()
        for a in PackActivity.allCases where acts.contains(a) {
            for g in list(gearBy[a.rawValue]) where gearSeen.insert(g["item"] as? String ?? "").inserted {
                gear.append(PackItem(id: "g-\(gear.count)", title: g["item"] as? String ?? "", detail: g["why"] as? String, source: source(g)))
            }
        }
        sections.append(PackSection(id: "gear", title: "Gear for what you're doing", icon: "boot", items: gear))
        if acts.contains(where: { $0 != .camping && $0 != .fishing }) || acts.count > 1 {
            let ess = dict(guide["essentials"])
            let items = list(ess["items"]).map { e in
                PackItem(id: "x-\(e["name"] as? String ?? "")", title: e["name"] as? String ?? "", detail: e["detail"] as? String, source: ess["source"] as? String)
            }
            sections.append(PackSection(id: "essentials", title: "The Ten Essentials", icon: "compass",
                                        summary: "The Park Service's list for anyone heading out from camp.", items: items))
        }
        if input.bearCountry {
            let bears = list(dict(guide["wildlife"])["bearCountryFoodStorage"]).enumerated().map { i, b in
                PackItem(id: "b-\(i)", title: b["guidance"] as? String ?? "", detail: nil, source: source(b))
            }
            sections.append(PackSection(id: "bears", title: "Bear country", icon: "warning",
                                        summary: "Bears have been recorded near here. Store food the way the Park Service says.", items: bears))
        }
        return sections.filter { !$0.items.isEmpty || $0.summary != nil }
    }
}
