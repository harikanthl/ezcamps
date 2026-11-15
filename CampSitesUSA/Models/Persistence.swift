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

    init(site: Site, date: Date, rating: Int, tags: [String], note: String, verified: Bool) {
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
        "Quiet", "Level spots", "Good cell signal", "No signal", "Clean",
        "Shade", "Great views", "Dark skies", "Rough road", "Crowded", "Big-rig friendly",
    ]
}

@Model
final class Trip {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \TripStop.trip) var stops: [TripStop] = []

    init(name: String) {
        self.name = name
        createdAt = .now
    }

    var orderedStops: [TripStop] { stops.sorted { $0.order < $1.order } }
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
