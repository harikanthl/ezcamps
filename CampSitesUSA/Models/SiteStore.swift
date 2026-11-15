import Foundation
import MapKit
import Observation

struct SiteFilter: Equatable {
    var freeOnly = false
    var kinds: Set<Site.Kind> = []          // empty = all kinds
    var amenities: Set<Amenity> = []        // all must be present
    var query = ""

    var isActive: Bool { freeOnly || !kinds.isEmpty || !amenities.isEmpty || !query.isEmpty }

    func matches(_ s: Site) -> Bool {
        if freeOnly && !s.likelyFree { return false }
        if !kinds.isEmpty && !kinds.contains(s.kind) { return false }
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

    func site(id: String) -> Site? { byID[id] }

    func load() async {
        guard !isLoaded, let url = Bundle.main.url(forResource: "sites", withExtension: "json") else { return }
        let dataset = await Task.detached(priority: .userInitiated) { () -> SiteDataset? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SiteDataset.self, from: data)
        }.value
        guard let dataset else { return }
        sites = dataset.sites
        attribution = dataset.attribution
        byID = Dictionary(dataset.sites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        isLoaded = true
    }

    /// Sites inside `region` that match `filter`, capped at `limit` so the map stays fast.
    /// When over the cap, sites are sampled evenly across a grid so the whole view stays covered
    /// (not one blob in the middle). Returns the total match count too, for the "zoom in" hint.
    func visible(in region: MKCoordinateRegion, filter: SiteFilter, limit: Int = 300) -> (sites: [Site], total: Int) {
        let c = region.center, s = region.span
        let minLat = c.latitude - s.latitudeDelta / 2, maxLat = c.latitude + s.latitudeDelta / 2
        let minLon = c.longitude - s.longitudeDelta / 2, maxLon = c.longitude + s.longitudeDelta / 2
        let inView = sites.filter {
            $0.lat >= minLat && $0.lat <= maxLat && $0.lon >= minLon && $0.lon <= maxLon && filter.matches($0)
        }
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
