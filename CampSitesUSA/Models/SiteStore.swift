import Foundation
import MapKit
import Observation

struct SiteFilter: Equatable {
    var freeOnly = false
    /// Kinds shown on the map. Dispersed is off by default: thousands of mostly-unnamed
    /// points crowd the map. One tap on the chip brings them back.
    var kinds: Set<Site.Kind> = SiteFilter.defaultKinds
    static let defaultKinds: Set<Site.Kind> = [.campground, .rvPark]
    var amenities: Set<Amenity> = []        // all must be present
    var query = ""

    var isActive: Bool { freeOnly || kinds != Self.defaultKinds || !amenities.isEmpty || !query.isEmpty }

    func matches(_ s: Site) -> Bool {
        if freeOnly && !s.likelyFree { return false }
        if !kinds.contains(s.kind) { return false }
        if !amenities.isEmpty && !amenities.allSatisfy({ s.amenities.contains($0.rawValue) }) { return false }
        if !query.isEmpty && !s.name.localizedCaseInsensitiveContains(query)
            && !(s.agency?.localizedCaseInsensitiveContains(query) ?? false) { return false }
        return true
    }
}

@Observable
final class SiteStore {
    private(set) var sites: [Site] = []
    private(set) var attribution = ""
    private(set) var isLoaded = false
    private var byID: [String: Site] = [:]
    private var grid = SiteGrid()
    private var isLoading = false
    private(set) var activities: [Activity] = []

    func site(id: String) -> Site? { byID[id] }

    func load() async {
        // `.task` re-runs if the root view is rebuilt; decode the 29k-site bundle once.
        guard !isLoaded, !isLoading, let url = Bundle.main.url(forResource: "sites", withExtension: "json") else { return }
        isLoading = true
        defer { isLoading = false }
        let built = await Task.detached(priority: .userInitiated) { () -> (SiteDataset, [String: Site], SiteGrid)? in
            guard let data = try? Data(contentsOf: url),
                  let dataset = try? JSONDecoder().decode(SiteDataset.self, from: data) else { return nil }
            let byID = Dictionary(dataset.sites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return (dataset, byID, SiteGrid(dataset.sites))
        }.value
        guard let (dataset, byID, grid) = built else { return }
        sites = dataset.sites
        attribution = dataset.attribution
        self.byID = byID
        self.grid = grid
        isLoaded = true

        if let aURL = Bundle.main.url(forResource: "activities", withExtension: "json") {
            activities = await Task.detached(priority: .utility) { () -> [Activity] in
                guard let data = try? Data(contentsOf: aURL) else { return [] }
                return (try? JSONDecoder().decode(ActivityDataset.self, from: data))?.activities ?? []
            }.value
        }
    }

    /// Sites within `radius` miles of a point (unsorted).
    func sites(near c: CLLocationCoordinate2D, radius: Double) -> [Site] {
        let dLat = radius / 69.0
        let dLon = radius / (69.0 * max(0.2, cos(c.latitude * .pi / 180)))
        return Array(grid.indices(minLat: c.latitude - dLat, maxLat: c.latitude + dLat,
                                  minLon: c.longitude - dLon, maxLon: c.longitude + dLon)
            .lazy.map { self.sites[$0] }
            .filter { TripPlanner.miles($0.coordinate, c) <= radius })
    }

    /// Activities within `radius` miles of a point, ranked by difficulty (Easy first, unrated last),
    /// then by distance.
    func activities(near c: CLLocationCoordinate2D, radius: Double = 25) -> [NearbyActivity] {
        let dLat = radius / 69.0
        let dLon = radius / (69.0 * max(0.2, cos(c.latitude * .pi / 180)))
        return activities.lazy
            .filter { abs($0.lat - c.latitude) <= dLat && abs($0.lon - c.longitude) <= dLon }
            .map { NearbyActivity(activity: $0, distance: $0.miles(from: c)) }
            .filter { $0.distance <= radius }
            .sorted { a, b in
                let da = a.activity.difficulty?.rawValue ?? 99, db = b.activity.difficulty?.rawValue ?? 99
                return da != db ? da < db : a.distance < b.distance
            }
    }

    /// Sites inside `region` that match `filter`, capped at `limit` so the map stays fast.
    /// When over the cap, sites are sampled evenly across a grid so the whole view stays covered
    /// (not one blob in the middle). Returns the total match count too, for the "zoom in" hint.
    func visible(in region: MKCoordinateRegion, filter: SiteFilter, limit: Int = 600) -> (sites: [Site], total: Int) {
        let c = region.center, s = region.span
        let minLat = c.latitude - s.latitudeDelta / 2, maxLat = c.latitude + s.latitudeDelta / 2
        let minLon = c.longitude - s.longitudeDelta / 2, maxLon = c.longitude + s.longitudeDelta / 2
        // Bare placeholder points only appear when zoomed in to roughly 25 km across.
        let showBare = s.latitudeDelta < 0.25 || !filter.query.isEmpty
        let inView = Array(grid.indices(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
            .lazy.map { self.sites[$0] }
            .filter {  // cells overhang the view; keep the exact box
                $0.lat >= minLat && $0.lat <= maxLat && $0.lon >= minLon && $0.lon <= maxLon
                    && (showBare || !$0.isBare) && filter.matches($0)
            })
        guard inView.count > limit else { return (inView, inView.count) }

        // Bucket into a cols×rows grid (roughly phone-shaped), then take sites round-robin across cells.
        let cols = 12, rows = 20
        var cells: [Int: [Site]] = [:]
        for site in inView {
            let cx = min(cols - 1, Int((site.lon - minLon) / s.longitudeDelta * Double(cols)))
            let cy = min(rows - 1, Int((site.lat - minLat) / s.latitudeDelta * Double(rows)))
            cells[cy * cols + cx, default: []].append(site)
        }
        // Prefer named and free sites within each cell so the sample is the most useful.
        var buckets = cells.values.map { $0.sorted { score($0) > score($1) } }
        var picked: [Site] = []
        picked.reserveCapacity(limit)
        var round = 0
        while picked.count < limit {
            var added = false
            for i in buckets.indices where round < buckets[i].count {
                picked.append(buckets[i][round])
                added = true
                if picked.count == limit { break }
            }
            if !added { break }
            round += 1
        }
        buckets.removeAll()
        return (picked, inView.count)
    }

    private func score(_ s: Site) -> Int {
        (s.likelyFree ? 2 : 0) + (s.name.hasPrefix("Unnamed") || s.name == "Dispersed site" ? 0 : 1)
    }
}

/// Sites bucketed into half-degree cells (~35 mi), so "sites near here" looks at a few cells instead
/// of all 29k sites. Route searches ask this hundreds of times per trip.
nonisolated struct SiteGrid: Sendable {
    private static let cell = 0.5
    private var cells: [Int: [Int]] = [:]

    init() {}

    init(_ sites: [Site]) {
        for (i, s) in sites.enumerated() { cells[Self.key(Self.row(s.lat), Self.col(s.lon)), default: []].append(i) }
    }

    private static func row(_ lat: Double) -> Int { Int(((min(max(lat, -90), 90) + 90) / cell).rounded(.down)) }
    private static func col(_ lon: Double) -> Int { Int(((min(max(lon, -180), 180) + 180) / cell).rounded(.down)) }
    private static func key(_ r: Int, _ c: Int) -> Int { r * 1000 + c }

    /// Indices of sites inside the box, in ascending order (the dataset's order).
    func indices(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> [Int] {
        guard minLat <= maxLat, minLon <= maxLon else { return [] }
        var out: [Int] = []
        let r0 = Self.row(minLat), r1 = Self.row(maxLat), c0 = Self.col(minLon), c1 = Self.col(maxLon)
        for r in r0...r1 {
            for c in c0...c1 { if let ids = cells[Self.key(r, c)] { out.append(contentsOf: ids) } }
        }
        return out
    }
}
