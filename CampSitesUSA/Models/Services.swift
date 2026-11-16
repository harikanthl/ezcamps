import Foundation
import MapKit
import SwiftUI

/// Practical stops near a camp: fuel, groceries, police, and the nearest hospital (a safety question at
/// remote free sites). Live from Apple Maps' points of interest, so hours and closures are current.
enum ServiceKind: String, CaseIterable, Identifiable {
    case gas, groceries, hospital, police

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gas: "Gas"
        case .groceries: "Groceries"
        case .hospital: "Hospital"
        case .police: "Police"
        }
    }

    var symbol: String {
        switch self {
        case .gas: "fuelpump.fill"
        case .groceries: "cart.fill"
        case .hospital: "cross.case.fill"
        case .police: "shield.fill"
        }
    }

    var categories: [MKPointOfInterestCategory] {
        switch self {
        case .gas: [.gasStation, .evCharger]
        case .groceries: [.foodMarket, .store]
        case .hospital: [.hospital]
        case .police: [.police]
        }
    }

    var query: String {
        switch self {
        case .gas: "gas station"
        case .groceries: "grocery store"
        case .hospital: "hospital emergency room"
        case .police: "police station"
        }
    }

    /// Search box sizes in miles, widening in empty country (a 95-mile hospital is worth knowing).
    var radii: [Double] {
        switch self {
        case .gas, .groceries: [30, 80]
        case .hospital: [40, 150]
        case .police: [30, 80]
        }
    }
}

struct ServicePlace: Identifiable {
    let id = UUID()
    let kind: ServiceKind
    let name: String
    let coordinate: CLLocationCoordinate2D
    let miles: Double
    let item: MKMapItem
}

/// Result for one camp: the nearest place of each kind, or nil when none was found within the
/// widest radius (worth saying out loud, especially for hospitals).
struct CampServices {
    var places: [ServiceKind: ServicePlace] = [:]
    var searched: Set<ServiceKind> = []
}

enum ServiceFinder {
    /// Text search limited to the right categories. (MKLocalPointsOfInterestRequest returned
    /// nothing outside towns in testing, so it isn't used.)
    static func nearest(_ kind: ServiceKind, to c: CLLocationCoordinate2D) async -> ServicePlace? {
        // Police also counts sheriff's offices and ranger stations: on public land that's who answers.
        if kind == .police { return await nearestLawEnforcement(to: c) }
        for radius in kind.radii {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = kind.query
            let meters = radius * 2 * TripPlanner.metersPerMile
            req.region = MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters)
            req.resultTypes = .pointOfInterest
            req.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.categories)
            guard let items = try? await MKLocalSearch(request: req).start().mapItems, !items.isEmpty else { continue }
            let ranked = items
                .filter { kind != .groceries || isGrocery($0) }
                .filter { kind != .hospital || isEmergencyCapable($0) }
                .map { ($0, TripPlanner.miles(c, $0.location.coordinate)) }
                .filter { $0.1 <= radius }
                .sorted { $0.1 < $1.1 }
            if let (item, miles) = ranked.first {
                return ServicePlace(kind: kind, name: item.name ?? kind.label, coordinate: item.location.coordinate,
                                    miles: miles, item: item)
            }
        }
        return nil
    }

    /// Skip places that won't treat a hurt camper: psychiatric, veterinary, rehab.
    private static func isEmergencyCapable(_ item: MKMapItem) -> Bool {
        let n = (item.name ?? "").lowercased()
        return !["state hospital", "psychiatric", "behavioral", "veterinary", "animal", "rehab", "hospice",
                 "mental", "pet "].contains { n.contains($0) }
    }

    /// `.store` is broad (it includes gift shops); keep food markets and stores that sound like groceries.
    private static func isGrocery(_ item: MKMapItem) -> Bool {
        if item.pointOfInterestCategory == .foodMarket { return true }
        let n = (item.name ?? "").lowercased()
        return ["market", "grocery", "foods", "safeway", "walmart", "kroger", "albertsons", "smith", "fred meyer",
                "whole foods", "trader joe", "dollar general", "family dollar", "general store", "mercantile",
                "co-op", "supermarket", "costco", "target", "winco", "heb", "publix", "aldi"].contains { n.contains($0) }
    }

    static func services(near c: CLLocationCoordinate2D) async -> CampServices {
        var out = CampServices()
        await withTaskGroup(of: (ServiceKind, ServicePlace?).self) { group in
            for kind in ServiceKind.allCases {
                group.addTask { (kind, await nearest(kind, to: c)) }
            }
            for await (kind, place) in group {
                out.searched.insert(kind)
                if let place { out.places[kind] = place }
            }
        }
        return out
    }
}

extension ServiceKind {
    var color: Color {
        switch self {
        case .gas: .canyon
        case .groceries: .meadow
        case .hospital: .berry
        case .police: .sky
        }
    }
}
