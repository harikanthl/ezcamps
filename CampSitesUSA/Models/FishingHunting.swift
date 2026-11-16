import Foundation
import CoreLocation

// Fishing and hunting near a campsite: species recorded nearby (iNaturalist, through the ratings
// Worker), live river flow (USGS), and the state's license rules (bundled licenses.json, from each
// state wildlife agency). Records show what people have seen and identified, not a guarantee.

// MARK: - Wildlife recorded nearby

nonisolated struct NearbySpecies: Codable, Sendable, Identifiable, Equatable {
    var name: String
    var scientific: String
    var observations: Int
    /// iNaturalist lists it as threatened somewhere it applies; rules vary, so check before keeping.
    var `protected`: Bool
    var game: Bool?
    var kind: String?   // "mammal" | "bird" for game

    var id: String { scientific }
}

nonisolated struct NearbyWildlife: Codable, Sendable, Equatable {
    var radiusKm: Int
    var fish: [NearbySpecies]
    var game: [NearbySpecies]
    var source: String

    var gameFish: [NearbySpecies] { fish.filter { $0.game == true } }
    var otherFish: [NearbySpecies] { fish.filter { $0.game != true } }
}

extension RatingsAPI {
    static func wildlife(near c: CLLocationCoordinate2D) async throws -> NearbyWildlife {
        var comps = URLComponents(url: base.appending(path: "/v1/wildlife"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "lat", value: String(format: "%.3f", c.latitude)),
                            .init(name: "lng", value: String(format: "%.3f", c.longitude))]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(NearbyWildlife.self, from: data)
    }
}

// MARK: - River flow (USGS Water Services, live)

nonisolated struct StreamGauge: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let cfs: Double
    let coordinate: CLLocationCoordinate2D
    let miles: Double
    let updated: Date?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.cfs == b.cfs }
}

enum StreamFlow {
    /// Active stream gauges reporting discharge within ~15 miles, nearest first.
    static func gauges(near c: CLLocationCoordinate2D) async -> [StreamGauge]? {
        let d = 0.22
        let box = String(format: "%.3f,%.3f,%.3f,%.3f", c.longitude - d, c.latitude - d, c.longitude + d, c.latitude + d)
        guard let url = URL(string: "https://waterservices.usgs.gov/nwis/iv/?format=json&bBox=\(box)&parameterCd=00060&siteStatus=active") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("ezcamp-ios", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let series = (root["value"] as? [String: Any])?["timeSeries"] as? [[String: Any]] else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var out: [StreamGauge] = []
        for s in series {
            guard let info = s["sourceInfo"] as? [String: Any],
                  let name = info["siteName"] as? String,
                  let code = (info["siteCode"] as? [[String: Any]])?.first?["value"] as? String,
                  let geo = (info["geoLocation"] as? [String: Any])?["geogLocation"] as? [String: Any],
                  let lat = geo["latitude"] as? Double, let lon = geo["longitude"] as? Double,
                  let last = ((s["values"] as? [[String: Any]])?.first?["value"] as? [[String: Any]])?.last,
                  let raw = last["value"] as? String, let cfs = Double(raw), cfs >= 0 else { continue }
            let at = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            let when = (last["dateTime"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            out.append(StreamGauge(id: code, name: Self.tidy(name), cfs: cfs, coordinate: at,
                                   miles: TripPlanner.miles(c, at), updated: when))
        }
        return out.sorted { $0.miles < $1.miles }
    }

    /// "VIRGIN RIVER AT VIRGIN, UT" → "Virgin River at Virgin, UT".
    static func tidy(_ raw: String) -> String {
        var parts = raw.components(separatedBy: ", ")
        let state = parts.count > 1 && parts.last!.count == 2 ? parts.removeLast() : nil
        let small: Set<String> = ["at", "near", "nr", "above", "below", "of", "the", "and", "in", "on"]
        let words = parts.joined(separator: ", ").capitalized.split(separator: " ").enumerated().map { i, w in
            i > 0 && small.contains(w.lowercased()) ? w.lowercased() : String(w)
        }
        return words.joined(separator: " ") + (state.map { ", \($0.uppercased())" } ?? "")
    }
}

// MARK: - State license rules (bundled)

nonisolated struct StateLicenses: Codable, Sendable {
    struct Fishing: Codable, Sendable {
        var licenseUrl: String?
        var regulationsUrl: String?
        var licenseRequiredFromAge: Int?
        var fishingNote: String?
        var freeFishingDays: String?
    }
    struct Hunting: Codable, Sendable {
        var licenseUrl: String?
        var regulationsUrl: String?
        var hunterEducation: String?
        var blazeOrange: String?
    }
    var state: String
    var agency: String?
    var agencyUrl: String?
    var fishing: Fishing?
    var hunting: Hunting?
}

enum LicenseBook {
    /// licenses.json: state wildlife agency rules (and a "US" entry for federal rules).
    static let all: [String: StateLicenses] = {
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([StateLicenses].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.state, $0) }, uniquingKeysWith: { a, _ in a })
    }()

    static func state(_ code: String) -> StateLicenses? { all[code.uppercased()] }
}
