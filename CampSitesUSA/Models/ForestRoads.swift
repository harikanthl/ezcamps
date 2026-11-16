import Foundation
import MapKit

/// USDA Forest Service Motor Vehicle Use Map (MVUM): the official map of which national-forest roads
/// and trails are open, to which vehicles, and in which season. Public domain. The service renders
/// on demand (no tile cache), so each tile is an `export` image, drawn only from zoom 10 in.
nonisolated enum ForestRoadsService {
    static let base = "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_MVUM_01/MapServer"
    static let minZoom = 10
}

final class ForestRoadsOverlay: MKTileOverlay {
    private static let cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 30 * 1024 * 1024
        return c
    }()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 10 << 20, diskCapacity: 100 << 20)
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() {
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        minimumZ = ForestRoadsService.minZoom
        maximumZ = 18
    }

    /// Web Mercator bounds of the tile, as an MVUM export request (roads + trails, transparent PNG).
    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let o = 20_037_508.342789244
        let size = 2 * o / Double(1 << path.z)
        let xmin = -o + Double(path.x) * size, xmax = xmin + size
        let ymax = o - Double(path.y) * size, ymin = ymax - size
        let scale = Int(path.contentScaleFactor.rounded())
        let px = 256 * max(scale, 1)
        return URL(string: "\(ForestRoadsService.base)/export?bbox=\(xmin),\(ymin),\(xmax),\(ymax)&bboxSR=3857&imageSR=3857&size=\(px),\(px)&dpi=\(96 * max(scale, 1))&format=png32&transparent=true&layers=show:1,2&f=image")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = url(forTilePath: path)
        let key = url.absoluteString as NSString
        if let hit = Self.cache.object(forKey: key) { result(hit as Data, nil); return }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.assumesHTTP3Capable = false
        req.setValue("ezcamp-ios", forHTTPHeaderField: "User-Agent")
        Self.session.dataTask(with: req) { data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200,
               (response as? HTTPURLResponse)?.mimeType?.hasPrefix("image") == true {
                Self.cache.setObject(data as NSData, forKey: key, cost: data.count)
                result(data, nil)
            } else {
                result(nil, error)
            }
        }.resume()
    }
}

/// The forest road or motorized trail nearest a point, with who may drive it and when.
nonisolated struct ForestRoad: Sendable {
    let number: String          // "50071"
    let name: String?           // "Geyser Pass"
    let access: String          // "Roads open to all Vehicles, Seasonal"
    let datesOpen: String?      // "05/21-12/14"
    let surface: String?        // "Gravel road, suitable for passenger car"
    let district: String?
    let forest: String?
    let isTrail: Bool

    var title: String {
        let prefix = isTrail ? "Trail" : "FR"
        return [name, "\(prefix) \(number)"].compactMap { $0 }.joined(separator: " · ")
    }

    static func nearest(to c: CLLocationCoordinate2D) async -> ForestRoad? {
        let d = 0.05
        var comps = URLComponents(string: ForestRoadsService.base + "/identify")!
        comps.queryItems = [
            .init(name: "geometry", value: "\(c.longitude),\(c.latitude)"),
            .init(name: "geometryType", value: "esriGeometryPoint"),
            .init(name: "sr", value: "4326"),
            .init(name: "layers", value: "all:1,2"),
            .init(name: "tolerance", value: "20"),   // 20 px of a 400 px box ~9 km across ≈ 450 m
            .init(name: "mapExtent", value: "\(c.longitude - d),\(c.latitude - d),\(c.longitude + d),\(c.latitude + d)"),
            .init(name: "imageDisplay", value: "400,400,96"),
            .init(name: "returnGeometry", value: "false"),
            .init(name: "f", value: "json"),
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.setValue("ezcamp-ios", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], let first = results.first,
              let a = first["attributes"] as? [String: Any] else { return nil }
        func v(_ k: String) -> String? {
            guard let s = a[k] as? String, !s.isEmpty, s != "Null" else { return nil }
            return s
        }
        guard let number = v("ID") ?? v("ID for Map Label") else { return nil }
        let surface = v("SBS_SYMBOL_NAME").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return ForestRoad(
            number: number, name: v("Name").map { $0.capitalized },
            access: v("MVUM_Symbol_Name") ?? "Open to motor vehicles",
            datesOpen: v("Passenger Vehicle  (Dates Open)") ?? v("High Clearance Vehicles (Dates Open)")
                ?? v("ATV (Dates Open)") ?? v("Motorcyle (Dates Open)"),
            surface: surface, district: v("Ranger District Name"), forest: v("Forest Name"),
            isTrail: (first["layerId"] as? Int) == 2)
    }
}
