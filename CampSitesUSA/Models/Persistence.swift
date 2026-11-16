import Foundation
import SwiftData
import CoreLocation

@Model
final class SavedSite {
    @Attribute(.unique) var siteID: String
    var name: String
    var lat: Double
    var lon: Double
    var savedAt: Date

    init(site: Site) {
        siteID = site.id
        name = site.name
        lat = site.lat
        lon = site.lon
        savedAt = .now
    }
}

/// A night (or visit) the user logged at a site, with their rating.
/// `verified` is true when the phone's location was within `Visit.verifyRadius` of the site when it was logged.
/// That's the basis for trusted community ratings later.
@Model
final class Visit {
    static let verifyRadius: CLLocationDistance = 500

    var siteID: String
    var siteName: String
    var date: Date
    var rating: Int          // 1...5
    var tags: [String]
    var note: String
    var verified: Bool
    var createdAt: Date
    /// Cell report: carrier name (see CellSignal.carriers) and 0 none … 3 strong. Optional.
    var carrier: String?
    var signal: Int?
    /// Id of this rating on the shared ratings server (assigned on first upload).
    var remoteID: String?
    /// False until the latest version is on the server. Only uploaded when sharing is on.
    var synced: Bool = false

    /// The night camped, as the server stores it ("2026-11-15", in the phone's time zone).
    var visitDay: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    init(site: Site, date: Date, rating: Int, tags: [String], note: String, verified: Bool,
         carrier: String? = nil, signal: Int? = nil) {
        self.carrier = carrier
        self.signal = signal
        siteID = site.id
        siteName = site.name
        self.date = date
        self.rating = rating
        self.tags = tags
        self.note = note
        self.verified = verified
        createdAt = .now
    }

    /// Quick tags people can attach to a rating.
    static let tagOptions = [
        "Quiet", "Level spots", "Clean",
        "Shade", "Great views", "Dark skies", "Rough road", "Crowded", "Big-rig friendly",
    ]
}

@Model
final class Trip {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \TripStop.trip) var stops: [TripStop] = []
    /// Photos and videos from the trip (files live in Documents/Memories).
    @Relationship(deleteRule: .cascade, inverse: \Memory.trip) var memories: [Memory] = []

    // Route endpoints. Optional so trips made before route planning still load.
    var startName: String?
    var startLat: Double?
    var startLon: Double?
    var endName: String?
    var endLat: Double?
    var endLon: Double?
    var startDate: Date?
    /// Daily driving budget used to suggest overnight camps.
    var dailyMiles: Int = 250
    var preferFree: Bool = true

    init(name: String) {
        self.name = name
        createdAt = .now
    }

    var orderedStops: [TripStop] { stops.sorted { $0.order < $1.order } }
    var totalNights: Int { stops.map(\.nights).reduce(0, +) }

    var start: CLLocationCoordinate2D? {
        guard let startLat, let startLon else { return nil }
        return .init(latitude: startLat, longitude: startLon)
    }

    var end: CLLocationCoordinate2D? {
        guard let endLat, let endLon else { return nil }
        return .init(latitude: endLat, longitude: endLon)
    }

    /// Start, every stop, then the destination: the points the route drives through.
    var waypoints: [CLLocationCoordinate2D] {
        (start.map { [$0] } ?? []) + orderedStops.map(\.coordinate) + (end.map { [$0] } ?? [])
    }

    /// Re-number stops 0…n after an insert, move or delete.
    func renumber() {
        for (i, s) in orderedStops.enumerated() { s.order = i }
    }
}

@Model
final class TripStop {
    var siteID: String
    var name: String
    var lat: Double
    var lon: Double
    var order: Int
    var nights: Int
    var trip: Trip?
    /// True when the planner picked this camp (shown as "Suggested" until the user keeps or swaps it).
    var suggested: Bool = false

    init(site: Site, order: Int) {
        siteID = site.id
        name = site.name
        lat = site.lat
        lon = site.lon
        self.order = order
        nights = 1
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}
