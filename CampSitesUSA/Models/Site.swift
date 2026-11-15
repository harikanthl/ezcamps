import Foundation
import CoreLocation

/// A campsite from the bundled open-data dataset (built by scripts/build_db.py, exported by scripts/pipeline/export_app.py).
nonisolated struct Site: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable {
        case osm, nps, ridb, usfs, blm

        var label: String {
            switch self {
            case .osm: "OpenStreetMap"
            case .nps: "National Park Service"
            case .ridb: "Recreation.gov"
            case .usfs: "USDA Forest Service"
            case .blm: "Bureau of Land Management"
            }
        }
    }

    enum Kind: String, Codable, CaseIterable, Sendable {
        case campground, dispersed
        case rvPark = "rv_park"

        var label: String {
            switch self {
            case .campground: "Campground"
            case .dispersed: "Dispersed"
            case .rvPark: "RV park"
            }
        }

        var symbol: String {
            switch self {
            case .campground: "tent.fill"
            case .dispersed: "mountain.2.fill"
            case .rvPark: "bus.fill"
            }
        }
    }

    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let state: String
    let source: Source
    let kind: Kind
    let free: Bool?
    let fee: String?
    let reservable: Bool
    let agency: String?
    let url: String?
    let phone: String?
    let description: String?
    let amenities: [String]
    let maxVehicleLength: Double?
    let openingHours: String?
    /// e.g. "14 days". Mostly BLM and OSM `max_stay`.
    let stayLimit: String?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    /// A bare OSM point with a placeholder name and nothing else. Not useful (or trustworthy)
    /// as a pin until the map is zoomed in close; see SiteStore.visible.
    /// Has a real name (not one of the pipeline's placeholders).
    var isNamed: Bool { name != "Dispersed site" && name != "Unnamed campsite" }

    var isBare: Bool {
        (name == "Dispersed site" || name == "Unnamed campsite") && source == .osm
            && description == nil && amenities.isEmpty && fee == nil && free != true
    }

    /// Explicitly free, or a dispersed site with no fee information (dispersed camping on public land is almost always free).
    var likelyFree: Bool { free == true || (free == nil && kind == .dispersed) }

    var priceLabel: String {
        if free == true { return "Free" }
        if likelyFree { return "Likely free" }
        if let fee { return fee }
        if free == false { return "Fee" }
        return "Fee unknown"
    }
}

nonisolated struct SiteDataset: Codable, Sendable {
    let generated: String
    let attribution: String
    let sites: [Site]
}

/// Display metadata for amenity keys used in the dataset.
enum Amenity: String, CaseIterable, Identifiable {
    case water, toilets, showers, dump, electric, tents, rv, wifi
    case fireRing = "fire_ring"
    case picnicTable = "picnic_table"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .water: "Water"
        case .toilets: "Toilets"
        case .showers: "Showers"
        case .dump: "Dump station"
        case .electric: "Hookups"
        case .tents: "Tents OK"
        case .rv: "RVs OK"
        case .wifi: "Wi-Fi"
        case .fireRing: "Fire ring"
        case .picnicTable: "Picnic table"
        }
    }

    var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .toilets: "toilet.fill"
        case .showers: "shower.fill"
        case .dump: "arrow.down.to.line"
        case .electric: "bolt.fill"
        case .tents: "tent.fill"
        case .rv: "bus.fill"
        case .wifi: "wifi"
        case .fireRing: "flame.fill"
        case .picnicTable: "table.furniture.fill"
        }
    }
}
