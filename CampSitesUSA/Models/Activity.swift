import Foundation
import CoreLocation

/// Something to do near a campsite: a trail, a paddle, a ranger program…
/// Built by scripts/pipeline/activities.py, exported to activities.json.
nonisolated struct Activity: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case hike, bike, horse, ohv, climb, paddle, boat, swim, fish, snow, scenic, program, other

        var label: String {
            switch self {
            case .hike: "Hiking"
            case .bike: "Biking"
            case .horse: "Horseback"
            case .ohv: "Off-road"
            case .climb: "Climbing"
            case .paddle: "Paddling"
            case .boat: "Boating"
            case .swim: "Swimming"
            case .fish: "Fishing"
            case .snow: "Snow"
            case .scenic: "Scenic"
            case .program: "Programs"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .hike: "figure.hiking"
            case .bike: "figure.outdoor.cycle"
            case .horse: "figure.equestrian.sports"
            case .ohv: "car.side.fill"
            case .climb: "figure.climbing"
            case .paddle: "figure.water.fitness"
            case .boat: "sailboat.fill"
            case .swim: "figure.pool.swim"
            case .fish: "fish.fill"
            case .snow: "snowflake"
            case .scenic: "binoculars.fill"
            case .program: "person.2.fill"
            case .other: "sparkles"
            }
        }
    }

    /// 0 Easy … 3 Strenuous.
    enum Difficulty: Int, Codable, CaseIterable, Comparable, Sendable {
        case easy, moderate, hard, strenuous

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .easy: "Easy"
            case .moderate: "Moderate"
            case .hard: "Hard"
            case .strenuous: "Strenuous"
            }
        }
    }

    let id: String
    let name: String
    let type: Kind
    let difficulty: Difficulty?
    /// Where the grade came from, e.g. "Forest Service trail class 2 (rough), 6.1 mi".
    let basis: String?
    let lat: Double
    let lon: Double
    let miles: Double?
    let duration: String?
    let uses: String?
    let place: String?
    let url: String?
    let description: String?
    let source: String

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// Distance-only helper that avoids allocating CLLocations in tight loops.
    func miles(from c: CLLocationCoordinate2D) -> Double {
        let k = Double.pi / 180
        let x = (lon - c.longitude) * k * cos((lat + c.latitude) * k / 2)
        let y = (lat - c.latitude) * k
        return 3958.8 * (x * x + y * y).squareRoot()
    }
}

nonisolated struct ActivityDataset: Codable, Sendable {
    let generated: String
    let activities: [Activity]
}

/// An activity with its distance from a campsite.
struct NearbyActivity: Identifiable, Hashable {
    let activity: Activity
    let distance: Double  // miles
    var id: String { activity.id }
}
