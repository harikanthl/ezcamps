import Foundation
import MapKit

// Safety heads-up for a campsite: what campers reported, current park alerts, how far help is,
// and crime context for the county. Never about individual people, and every part shows its source.

// MARK: - Bundled index (scripts/pipeline/safety_index.py)

nonisolated struct CountyCrime: Codable, Sendable {
    var agency: String
    var violent: Double?
    var property: Double?
    var state_violent: Double?
    var state_property: Double?
    var us_violent: Double?
    var us_property: Double?
    var population: Int?
    var months: Int?
    var violentCount: Double?
    var propertyCount: Double?

    /// Under 5,000 people a few incidents swing the rate wildly, so show counts instead of a comparison.
    var isSmall: Bool { (population ?? 0) < 5000 }
}

nonisolated struct CountyInfo: Codable, Sendable {
    var name: String
    var state: String
    var crime: CountyCrime?
}

nonisolated struct SafetyIndex: Decodable, Sendable {
    var crimeYear: Int?
    var counties: [String: CountyInfo]
    private var sites: [String: Entry]

    /// "geoid", or [geoid | null, [park codes]].
    private struct Entry: Decodable, Sendable {
        var county: String?
        var parks: [String] = []

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                county = s
                return
            }
            var a = try decoder.unkeyedContainer()
            county = try a.decodeIfPresent(String.self)
            parks = (try? a.decode([String].self)) ?? []
        }
    }

    private enum CodingKeys: String, CodingKey { case crimeYear, counties, sites }

    func county(for siteID: String) -> CountyInfo? {
        sites[siteID]?.county.flatMap { counties[$0] }
    }

    func parks(for siteID: String) -> [String] { sites[siteID]?.parks ?? [] }

    static func load() -> SafetyIndex? {
        guard let url = Bundle.main.url(forResource: "safety_index", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SafetyIndex.self, from: data)
    }
}

/// How a county rate compares with the US: plain words, never a "danger score".
nonisolated enum CrimeComparison {
    case muchLower, lower, similar, higher, muchHigher

    init?(rate: Double?, us: Double?) {
        guard let rate, let us, us > 0 else { return nil }
        switch rate / us {
        case ..<0.5: self = .muchLower
        case ..<0.85: self = .lower
        case ..<1.2: self = .similar
        case ..<2: self = .higher
        default: self = .muchHigher
        }
    }

    var label: String {
        switch self {
        case .muchLower: "Well below the US rate"
        case .lower: "Below the US rate"
        case .similar: "About the US rate"
        case .higher: "Above the US rate"
        case .muchHigher: "Well above the US rate"
        }
    }
}

// MARK: - Camper safety tags

enum SafetyTag {
    /// Tags campers can add when rating. Shared with the server's allow-list.
    static let all = ["Felt safe", "Felt unsafe", "Car break-ins", "Harassed", "Rangers patrol", "Gate locked at night"]
    static let concerning: Set<String> = ["Felt unsafe", "Car break-ins", "Harassed"]
    static func isSafety(_ tag: String) -> Bool { all.contains(tag) }
}

// MARK: - Park alerts (NPS, through the ratings Worker)

nonisolated struct ParkAlert: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var park: String
    var title: String
    var description: String
    var category: String
    var url: String?

    /// Danger and closures first.
    var rank: Int {
        switch category {
        case "Danger": 0
        case "Park Closure": 1
        case "Caution": 2
        default: 3
        }
    }
}

extension RatingsAPI {
    static func alerts(parks: [String]) async throws -> [ParkAlert] {
        struct Out: Decodable { let alerts: [ParkAlert] }
        guard !parks.isEmpty else { return [] }
        var c = URLComponents(url: base.appending(path: "/v1/alerts"), resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "parks", value: parks.prefix(5).joined(separator: ","))]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Out.self, from: data).alerts
    }
}

// MARK: - Nearest help

extension ServiceFinder {
    /// Nearest police station, sheriff or ranger station (Apple Maps), widening in empty country.
    static func nearestLawEnforcement(to c: CLLocationCoordinate2D) async -> ServicePlace? {
        for radius in [30.0, 80] {
            let meters = radius * 2 * TripPlanner.metersPerMile
            var best: (MKMapItem, Double)?
            for (query, filter) in [("police station", MKPointOfInterestFilter(including: [.police])),
                                    ("ranger station", MKPointOfInterestFilter.includingAll)] {
                let req = MKLocalSearch.Request()
                req.naturalLanguageQuery = query
                req.region = MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters)
                req.resultTypes = .pointOfInterest
                req.pointOfInterestFilter = filter
                guard let items = try? await MKLocalSearch(request: req).start().mapItems else { continue }
                for item in items {
                    let name = (item.name ?? "").lowercased()
                    // "ranger station" text search also returns unrelated shops; keep official-sounding places.
                    if query == "ranger station" && !(name.contains("ranger") || name.contains("visitor center") || name.contains("district office")) { continue }
                    let d = TripPlanner.miles(c, item.location.coordinate)
                    if d <= radius && d < (best?.1 ?? .infinity) { best = (item, d) }
                }
            }
            if let (item, d) = best {
                return ServicePlace(kind: .police, name: item.name ?? "Police", coordinate: item.location.coordinate, miles: d, item: item)
            }
        }
        return nil
    }
}
