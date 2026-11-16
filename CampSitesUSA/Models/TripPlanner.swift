import Foundation
import MapKit
import SwiftData
import Observation

/// Route planning for trips: driving legs, overnight camp suggestions along the route,
/// alternatives for a stop, and inserting a site where it adds the least detour.
enum TripPlanner {
    static let metersPerMile = 1609.344

    // MARK: Routing

    /// One MKRoute per consecutive pair of waypoints (nil where MapKit found no route).
    static func legs(through points: [CLLocationCoordinate2D]) async -> [MKRoute?] {
        guard points.count >= 2 else { return [] }
        var out: [MKRoute?] = []
        for (a, b) in zip(points, points.dropFirst()) {
            if Task.isCancelled { return [] }
            out.append(await route(from: a, to: b))
        }
        return out
    }

    static func route(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> MKRoute? {
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: a.latitude, longitude: a.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: b.latitude, longitude: b.longitude), address: nil)
        req.transportType = .automobile
        return try? await MKDirections(request: req).calculate().routes.first
    }

    // MARK: Suggestions

    /// Overnight points along the route. The drive is split into equal days no longer than
    /// `dailyMiles` (584 mi at 250/day becomes 3 days of ~195 mi, not 250 + 250 + 84).
    static func overnightPoints(on route: MKRoute, dailyMiles: Int) -> [CLLocationCoordinate2D] {
        let poly = route.polyline
        let pts = UnsafeBufferPointer(start: poly.points(), count: poly.pointCount)
        guard pts.count > 1 else { return [] }
        let budget = Double(dailyMiles) * metersPerMile
        // Polyline length, not route.distance, so the targets land on the drawn line.
        var lengths = [0.0]
        for i in 1..<pts.count { lengths.append(lengths[i - 1] + pts[i - 1].distance(to: pts[i])) }
        let total = lengths.last!
        // A little slack so a 260 mi drive at 250/day stays one day.
        let days = Int((total / (budget * 1.08)).rounded(.up))
        guard days > 1 else { return [] }
        let step = total / Double(days)
        var targets: [CLLocationCoordinate2D] = []
        var i = 1
        for k in 1..<days {
            let want = step * Double(k)
            while i < pts.count - 1 && lengths[i] < want { i += 1 }
            let seg = max(lengths[i] - lengths[i - 1], 1)
            let t = (want - lengths[i - 1]) / seg
            targets.append(MKMapPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                                      y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t).coordinate)
        }
        return targets
    }

    /// How good a site is as an overnight stop near `target` (higher is better).
    static func score(_ s: Site, target: CLLocationCoordinate2D, preferFree: Bool) -> Double {
        var v = 0.0
        if preferFree && s.likelyFree { v += 4 }
        if s.free == true { v += 1 }
        if s.kind == .campground { v += 1 }
        if s.description != nil { v += 1 }
        v += min(Double(s.amenities.count), 5) * 0.3
        if s.source == .nps || s.source == .ridb || s.source == .usfs || s.source == .blm { v += 1 }
        v -= miles(s.coordinate, target) * 0.15
        return v
    }

    /// Ranked campsites near a point. Bare placeholder points are never suggested.
    static func candidates(near target: CLLocationCoordinate2D, in store: SiteStore, radius: Double = 20,
                           preferFree: Bool, excluding: Set<String> = []) -> [Site] {
        store.sites(near: target, radius: radius)
            .filter { $0.isNamed && !$0.isBare && !excluding.contains($0.id) }  // only suggest camps people can look up
            .sorted { score($0, target: target, preferFree: preferFree) > score($1, target: target, preferFree: preferFree) }
    }

    /// Best camp at each day's end along the route.
    static func suggestStops(on route: MKRoute, dailyMiles: Int, preferFree: Bool, store: SiteStore) -> [Site] {
        var used = Set<String>()
        var out: [Site] = []
        for target in overnightPoints(on: route, dailyMiles: dailyMiles) {
            // Widen the search in empty country rather than leave a night unplanned.
            let pick = candidates(near: target, in: store, preferFree: preferFree, excluding: used).first
                ?? candidates(near: target, in: store, radius: 45, preferFree: preferFree, excluding: used).first
            if let pick {
                used.insert(pick.id)
                out.append(pick)
            }
        }
        return out
    }

    /// Campsites within `radius` miles of any point on the route, nearest-to-route first.
    static func sitesAlong(_ routes: [MKRoute], in store: SiteStore, radius: Double = 8, limit: Int = 60) -> [Site] {
        var samples: [CLLocationCoordinate2D] = []
        for r in routes {
            let poly = r.polyline
            let pts = UnsafeBufferPointer(start: poly.points(), count: poly.pointCount)
            var acc = Double.infinity
            for i in pts.indices {
                if i > 0 { acc += pts[i - 1].distance(to: pts[i]) }
                if acc >= 5 * metersPerMile { samples.append(pts[i].coordinate); acc = 0 }
            }
        }
        var best: [String: (Site, Double)] = [:]
        for p in samples {
            for s in store.sites(near: p, radius: radius) where !s.isBare {
                let d = miles(s.coordinate, p)
                if d < best[s.id]?.1 ?? .infinity { best[s.id] = (s, d) }
            }
        }
        return best.values.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    // MARK: Building a trip

    enum PlanError: LocalizedError {
        case noStart, notFound(String), noRoute
        var errorDescription: String? {
            switch self {
            case .noStart: "Turn on location, or say where you're starting from."
            case .notFound(let place): "Couldn't find “\(place)”. Try a city or park name."
            case .noRoute: "Couldn't find a driving route between those places."
            }
        }
    }

    /// Resolve a place name (city, park, address) to a coordinate with Apple Maps search.
    static func place(named name: String, near: CLLocationCoordinate2D? = nil) async -> TripPlace? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = name
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(center: near ?? .init(latitude: 39.5, longitude: -98.35),
                                        span: .init(latitudeDelta: 30, longitudeDelta: 60))
        guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return nil }
        return TripPlace(name: name, coordinate: item.location.coordinate)
    }

    /// Build and insert a trip: drive start → via places → destination, a camp near each via place,
    /// overnight camps every day's drive in between, and any extra requested nights added to the
    /// via camps first, then the last camp. Every camp comes from ezcamps' data.
    static func makeTrip(from start: TripPlace, to end: TripPlace, via: [TripPlace] = [], startDate: Date?,
                         dailyMiles: Int, preferFree: Bool, totalNights: Int? = nil,
                         store: SiteStore, context: ModelContext) async throws -> Trip {
        let points = [start] + via + [end]
        var legs: [MKRoute] = []
        for (a, b) in zip(points, points.dropFirst()) {
            guard let r = await route(from: a.coordinate, to: b.coordinate) else { throw PlanError.noRoute }
            legs.append(r)
        }
        // Routing takes a few seconds; if the person cancelled meanwhile, save nothing.
        try Task.checkCancellation()
        let trip = Trip(name: "\(start.name) → \(end.name)")
        trip.startName = start.name
        trip.startLat = start.coordinate.latitude
        trip.startLon = start.coordinate.longitude
        trip.endName = end.name
        trip.endLat = end.coordinate.latitude
        trip.endLon = end.coordinate.longitude
        trip.startDate = startDate
        trip.dailyMiles = dailyMiles
        trip.preferFree = preferFree
        context.insert(trip)

        var used = Set<String>()
        var viaStops: [TripStop] = []
        func add(_ site: Site, suggested: Bool) -> TripStop {
            used.insert(site.id)
            let stop = TripStop(site: site, order: trip.stops.count)
            stop.suggested = suggested
            trip.stops.append(stop)
            return stop
        }
        for (i, leg) in legs.enumerated() {
            for site in suggestStops(on: leg, dailyMiles: dailyMiles, preferFree: preferFree, store: store)
            where !used.contains(site.id) {
                _ = add(site, suggested: true)
            }
            // Stay at each via place: the best camp near it.
            if i < via.count, let camp = candidates(near: via[i].coordinate, in: store, radius: 30,
                                                    preferFree: preferFree, excluding: used).first {
                viaStops.append(add(camp, suggested: true))
            }
        }
        // Requested nights beyond one per camp: via places first (that's where people want time), then the last camp.
        if let total = totalNights, total > trip.totalNights {
            var extra = total - trip.totalNights
            if trip.stops.isEmpty, let camp = candidates(near: end.coordinate, in: store, radius: 30,
                                                          preferFree: preferFree, excluding: used).first {
                let stop = add(camp, suggested: true)
                stop.nights = 0
                extra = total
            }
            let targets = viaStops.isEmpty ? Array(trip.orderedStops.suffix(1)) : viaStops
            var i = 0
            while extra > 0, !targets.isEmpty {
                let t = targets[i % targets.count]
                if t.nights < 14 { t.nights += 1; extra -= 1 }
                i += 1
                if i > 14 * targets.count { break }
            }
        }
        return trip
    }

    // MARK: Editing

    /// Insert `site` into the trip where it adds the least straight-line detour.
    @discardableResult
    static func insert(_ site: Site, into trip: Trip, suggested: Bool = false) -> TripStop? {
        guard !trip.stops.contains(where: { $0.siteID == site.id }) else { return nil }
        let points = trip.waypoints
        let hasStart = trip.start != nil
        var bestIndex = trip.stops.count  // append by default (before the destination)
        if points.count >= 2 {
            var bestCost = Double.infinity
            for i in 0..<(points.count - 1) {
                let cost = miles(points[i], site.coordinate) + miles(site.coordinate, points[i + 1]) - miles(points[i], points[i + 1])
                if cost < bestCost { bestCost = cost; bestIndex = hasStart ? i : i + 1 }
            }
            // Open-ended trips (no destination) can also grow at the end.
            if trip.end == nil, let last = points.last, miles(last, site.coordinate) < bestCost {
                bestIndex = trip.stops.count
            }
            bestIndex = min(max(bestIndex, 0), trip.stops.count)
        }
        let stops = trip.orderedStops
        for s in stops where s.order >= bestIndex { s.order += 1 }
        let stop = TripStop(site: site, order: bestIndex)
        stop.suggested = suggested
        trip.stops.append(stop)
        trip.renumber()
        return stop
    }

    static func miles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let k = Double.pi / 180
        let x = (b.longitude - a.longitude) * k * cos((a.latitude + b.latitude) * k / 2)
        let y = (b.latitude - a.latitude) * k
        return 3958.8 * (x * x + y * y).squareRoot()
    }
}

// MARK: - Place search

/// A place the user picked for a trip's start or destination.
struct TripPlace: Equatable {
    let name: String
    let coordinate: CLLocationCoordinate2D

    static func == (a: Self, b: Self) -> Bool {
        a.name == b.name && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// Autocomplete for cities, parks and addresses (MKLocalSearchCompleter).
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" { didSet { completer.queryFragment = query } }
    private(set) var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(center: .init(latitude: 39.5, longitude: -98.35),
                                              span: .init(latitudeDelta: 30, longitudeDelta: 60))
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        Task { @MainActor in self.results = Array(r.prefix(8)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> TripPlace? {
        let req = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return nil }
        return TripPlace(name: completion.title, coordinate: item.location.coordinate)
    }
}
