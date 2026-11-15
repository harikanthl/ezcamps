import Foundation

/// Contextual gear tips: shown only when the conditions call for it (a freezing night, rain, smoke,
/// off-grid nights, no signal, no water), never as a shop. Links are store searches; affiliate
/// parameters are added in one place once accounts exist, and the disclosure appears only then.
nonisolated struct GearTip: Identifiable, Sendable {
    enum Kind: Int { case cold, rain, smoke, offGrid, noCell, noWater }
    let kind: Kind
    let title: String
    let why: String
    let symbol: String
    let query: String
    var id: Int { kind.rawValue }
}

nonisolated enum GearLinks {
    struct Retailer: Identifiable, Sendable {
        let name: String
        let searchURL: @Sendable (String) -> URL?
        var id: String { name }
    }

    /// Affiliate parameters per retailer (e.g. AvantLink for REI, Impact for Backcountry).
    /// Empty until accounts exist; when set, links carry them and the UI shows a disclosure.
    static let affiliateParams: [String: [URLQueryItem]] = [:]

    static var hasAffiliates: Bool { !affiliateParams.isEmpty }

    static let retailers: [Retailer] = [
        Retailer(name: "REI") { q in link("https://www.rei.com/search", q: q, retailer: "REI") },
        Retailer(name: "Backcountry") { q in link("https://www.backcountry.com/Store/catalog/search.jsp", q: q, retailer: "Backcountry") },
    ]

    private static func link(_ base: String, q: String, retailer: String) -> URL? {
        var c = URLComponents(string: base)
        c?.queryItems = [URLQueryItem(name: "q", value: q)] + (affiliateParams[retailer] ?? [])
        return c?.url
    }
}

nonisolated enum GearAdvisor {
    /// Up to `limit` tips, most important first.
    /// - nights: forecasts for the nights in question; aqi: overnight AQI values;
    ///   sites: the camps involved, with how many nights at each.
    static func tips(nights: [NightForecast], aqi: [Int], sites: [(site: Site, nights: Int)], limit: Int = 3) -> [GearTip] {
        var out: [GearTip] = []
        if let coldest = nights.min(by: { $0.low < $1.low }), coldest.low <= 32 {
            let day = coldest.name == "Tonight" ? "tonight" : "on \(coldest.name.replacingOccurrences(of: " Night", with: ""))"
            out.append(coldest.low <= 20
                ? GearTip(kind: .cold, title: "Bitter cold night", why: "Low of \(coldest.low)°F \(day). A 0–15°F sleeping bag and an insulated pad (R-value 4+) keep you safe.",
                          symbol: "thermometer.snowflake", query: "0 degree sleeping bag")
                : GearTip(kind: .cold, title: "Freezing night", why: "Low of \(coldest.low)°F \(day). A 20°F sleeping bag and an insulated pad make it comfortable.",
                          symbol: "snowflake", query: "20 degree sleeping bag"))
        }
        if let wettest = nights.compactMap(\.precipChance).max(), wettest >= 50 {
            out.append(GearTip(kind: .rain, title: "Rain likely", why: "\(wettest)% chance overnight. A tarp over camp and dry bags for gear help.",
                               symbol: "cloud.rain.fill", query: "camping tarp"))
        }
        if let worst = aqi.max(), worst > 100 {
            out.append(GearTip(kind: .smoke, title: "Smoky air", why: "Overnight AQI up to \(worst). N95 masks filter wildfire smoke.",
                               symbol: "aqi.high", query: "N95 mask"))
        }
        let offGridNights = sites.filter { !$0.site.amenities.contains("electric") }.map(\.nights).reduce(0, +)
        if offGridNights >= 2 {
            out.append(GearTip(kind: .offGrid, title: "Off-grid nights", why: "\(offGridNights) nights without hookups. A portable power station or solar panel keeps phones, lights and a fridge going.",
                               symbol: "bolt.batteryblock.fill", query: "portable power station"))
        }
        if sites.contains(where: { $0.site.cell == "none" }) {
            out.append(GearTip(kind: .noCell, title: "No cell service", why: "No signal at camp. A satellite messenger can reach help anywhere.",
                               symbol: "antenna.radiowaves.left.and.right.slash", query: "satellite messenger"))
        }
        if sites.contains(where: { $0.site.kind == .dispersed && !$0.site.amenities.contains("water") }) {
            out.append(GearTip(kind: .noWater, title: "No water at camp", why: "Bring water jugs, or a filter if there's a stream nearby.",
                               symbol: "drop.triangle.fill", query: "water filter backpacking"))
        }
        return Array(out.prefix(limit))
    }
}
