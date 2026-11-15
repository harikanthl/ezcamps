import Foundation
import MapKit
import Observation
import UIKit

// MARK: - Tile cache on disk

/// Public-lands tiles saved for offline use: Application Support/Offline/tiles/z/x/y.png.
/// Shared by every state pack; the overlay reads from here before the network.
nonisolated enum TileCache {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appending(path: "Offline", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Re-downloadable data: keep it out of iCloud backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    static func url(z: Int, x: Int, y: Int) -> URL {
        root.appending(path: "tiles/\(z)/\(x)/\(y).png")
    }

    static func data(z: Int, x: Int, y: Int) -> Data? {
        try? Data(contentsOf: url(z: z, x: x, y: y))
    }

    static func write(_ data: Data, z: Int, x: Int, y: Int) {
        let u = url(z: z, x: x, y: y)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: u, options: .atomic)
    }

    /// For zooms beyond what was downloaded: crop and enlarge the nearest cached ancestor tile.
    static func overzoomed(z: Int, x: Int, y: Int) -> Data? {
        for up in 1...7 where z - up >= 0 {
            let pz = z - up, px = x >> up, py = y >> up
            guard let parent = data(z: pz, x: px, y: py), let image = UIImage(data: parent)?.cgImage else { continue }
            let n = 1 << up
            let size = CGFloat(image.width) / CGFloat(n)
            let rect = CGRect(x: CGFloat(x - (px << up)) * size, y: CGFloat(y - (py << up)) * size, width: size, height: size)
            guard let crop = image.cropping(to: rect) else { continue }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let out = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { ctx in
                ctx.cgContext.interpolationQuality = .none  // keep land boundaries crisp, not blurred
                UIImage(cgImage: crop).draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
            }
            return out.pngData()
        }
        return nil
    }
}

nonisolated enum TileMath {
    static func x(_ lon: Double, _ z: Int) -> Int {
        Int(((lon + 180) / 360 * Double(1 << z)).rounded(.down))
    }

    static func y(_ lat: Double, _ z: Int) -> Int {
        let r = lat * .pi / 180
        return Int(((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * Double(1 << z)).rounded(.down))
    }

    /// Pixel (0..<256) of a coordinate inside its tile at zoom z.
    static func pixel(_ c: CLLocationCoordinate2D, _ z: Int) -> (x: Int, y: Int, px: Int, py: Int) {
        let n = Double(1 << z)
        let fx = (c.longitude + 180) / 360 * n
        let r = c.latitude * .pi / 180
        let fy = (1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n
        return (Int(fx), Int(fy), Int((fx - fx.rounded(.down)) * 256), Int((fy - fy.rounded(.down)) * 256))
    }
}

// MARK: - State packs

nonisolated struct StateBounds: Codable, Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
    var id: String { code }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        (minLat...maxLat).contains(c.latitude) && (minLon...maxLon).contains(c.longitude)
    }

    var area: Double { (maxLat - minLat) * (maxLon - minLon) }

    static let minZoom = 5
    static let tileBudget = 8_000  // ~25 MB of public-lands tiles

    func tileCount(maxZoom: Int) -> Int {
        (Self.minZoom...maxZoom).reduce(0) { n, z in
            n + (TileMath.x(maxLon, z) - TileMath.x(minLon, z) + 1) * (TileMath.y(minLat, z) - TileMath.y(maxLat, z) + 1)
        }
    }

    /// Deepest zoom (≤ 12) that fits the tile budget. Closer zooms are enlarged from it.
    var packZoom: Int {
        (Self.minZoom...12).last { tileCount(maxZoom: $0) <= Self.tileBudget } ?? Self.minZoom
    }

    func tiles() -> [(z: Int, x: Int, y: Int)] {
        var out: [(Int, Int, Int)] = []
        for z in Self.minZoom...packZoom {
            for x in TileMath.x(minLon, z)...TileMath.x(maxLon, z) {
                for y in TileMath.y(maxLat, z)...TileMath.y(minLat, z) { out.append((z, x, y)) }
            }
        }
        return out
    }

    /// Rough size before downloading (public-lands tiles average ~3.5 KB).
    var estimatedMB: Double { Double(tileCount(maxZoom: packZoom)) * 3.5 / 1024 }
}

nonisolated struct OfflinePack: Codable, Sendable {
    let code: String
    let zoom: Int
    var tiles: Int
    var bytes: Int
    var downloadedAt: Date
}

@Observable
final class OfflineStore {
    private(set) var states: [StateBounds] = []
    private(set) var packs: [String: OfflinePack] = [:]
    private(set) var downloading: String?
    private(set) var progress: Double = 0
    private(set) var lastError: String?
    private var task: Task<Void, Never>?

    private static let manifest = TileCache.root.appending(path: "packs.json")

    init() {
        if let url = Bundle.main.url(forResource: "state_bounds", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            states = (try? JSONDecoder().decode([StateBounds].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: Self.manifest) {
            packs = (try? JSONDecoder().decode([String: OfflinePack].self, from: data)) ?? [:]
        }
    }

    var totalBytes: Int { packs.values.map(\.bytes).reduce(0, +) }

    func state(_ code: String) -> StateBounds? { states.first { $0.code == code } }

    /// Smallest state box containing the point (boxes overlap near borders).
    func stateCode(at c: CLLocationCoordinate2D) -> String? {
        states.filter { $0.contains(c) }.min { $0.area < $1.area }?.code
    }

    func download(_ codes: [String]) {
        guard downloading == nil else { return }
        task = Task { [weak self] in
            for code in codes where self?.packs[code] == nil {
                await self?.downloadOne(code)
                if Task.isCancelled { break }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        downloading = nil
        progress = 0
    }

    func delete(_ code: String) {
        guard let state = state(code) else { return }
        packs[code] = nil
        save()
        // Keep tiles that a neighbouring downloaded state still needs.
        let others = packs.keys.compactMap { self.state($0) }
        Task.detached(priority: .utility) {
            for t in state.tiles() {
                let shared = others.contains { o in
                    t.z <= o.packZoom && (TileMath.x(o.minLon, t.z)...TileMath.x(o.maxLon, t.z)).contains(t.x)
                        && (TileMath.y(o.maxLat, t.z)...TileMath.y(o.minLat, t.z)).contains(t.y)
                }
                if !shared { try? FileManager.default.removeItem(at: TileCache.url(z: t.z, x: t.x, y: t.y)) }
            }
        }
    }

    private func downloadOne(_ code: String) async {
        guard let state = state(code) else { return }
        downloading = code
        progress = 0
        lastError = nil
        defer { if downloading == code { downloading = nil } }

        let tiles = state.tiles()
        let session = URLSession(configuration: .ephemeral)
        var done = 0, bytes = 0, failed = 0
        // Six at a time: fast on a good connection, polite to the BLM server.
        await withTaskGroup(of: (Int, Bool).self) { group in
            var iterator = tiles.makeIterator()
            func addNext() -> Bool {
                guard let t = iterator.next() else { return false }
                group.addTask {
                    if let existing = try? Data(contentsOf: TileCache.url(z: t.z, x: t.x, y: t.y)) { return (existing.count, true) }
                    var req = URLRequest(url: URL(string: "\(PublicLandsService.base)/tile/\(t.z)/\(t.y)/\(t.x)")!, timeoutInterval: 30)
                    req.assumesHTTP3Capable = false
                    req.setValue("ezcamps-ios", forHTTPHeaderField: "User-Agent")
                    guard let (data, resp) = try? await session.data(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 200 else { return (0, false) }
                    TileCache.write(data, z: t.z, x: t.x, y: t.y)
                    return (data.count, true)
                }
                return true
            }
            for _ in 0..<6 { _ = addNext() }
            for await (size, ok) in group {
                if Task.isCancelled { group.cancelAll(); break }
                done += 1
                bytes += size
                if !ok { failed += 1 }
                if done % 25 == 0 || done == tiles.count { progress = Double(done) / Double(tiles.count) }
                _ = addNext()
            }
        }
        guard !Task.isCancelled else { return }
        // A few missing tiles (ocean edges, server hiccups) are fine; mostly-missing means no connection.
        if failed > tiles.count / 5 {
            lastError = "Couldn't download \(state.name). Check your connection and try again."
            return
        }
        packs[code] = OfflinePack(code: code, zoom: state.packZoom, tiles: tiles.count - failed, bytes: bytes, downloadedAt: .now)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(packs) { try? data.write(to: Self.manifest, options: .atomic) }
    }
}

// MARK: - Offline "Can I camp here?"

/// Without signal, read the land manager from the downloaded public-lands tile: each agency has a
/// distinct fill color in the BLM Surface Management Agency map (colors from its published legend).
nonisolated enum OfflineLand {
    private static let legend: [(code: String, rgb: (Int, Int, Int))] = [
        ("BLM", (254, 230, 121)), ("USFS", (204, 235, 197)), ("NPS", (202, 189, 220)),
        ("FWS", (127, 204, 167)), ("BOR", (255, 255, 179)), ("BIA", (253, 180, 108)),
        ("DOD", (251, 180, 206)), ("OTHFE", (228, 196, 159)), ("ST", (179, 227, 238)),
        ("LG", (143, 181, 190)), ("BIA", (207, 140, 75)), ("BIA", (137, 90, 68)),
    ]

    static func agency(at c: CLLocationCoordinate2D) -> String? {
        for z in stride(from: 12, through: StateBounds.minZoom, by: -1) {
            let p = TileMath.pixel(c, z)
            guard let data = TileCache.data(z: z, x: p.x, y: p.y), let image = UIImage(data: data)?.cgImage,
                  let rgba = pixel(image, x: p.px, y: p.py) else { continue }
            if rgba.3 < 40 { return "PVT" }  // transparent: no public manager mapped here
            let best = legend.min { distance($0.rgb, rgba) < distance($1.rgb, rgba) }!
            return distance(best.rgb, rgba) < 40 ? best.code : "UND"
        }
        return nil  // no offline tile covers this point
    }

    private static func distance(_ a: (Int, Int, Int), _ b: (Int, Int, Int, Int)) -> Int {
        abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int, Int)? {
        let sx = x * image.width / 256, sy = y * image.height / 256
        var buf = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &buf, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: -sx, y: sy - image.height + 1, width: image.width, height: image.height))
        let a = Int(buf[3])
        guard a > 0 else { return (0, 0, 0, 0) }
        // Un-premultiply so semi-transparent edges compare fairly.
        return (Int(buf[0]) * 255 / a, Int(buf[1]) * 255 / a, Int(buf[2]) * 255 / a, a)
    }
}
