import SwiftUI
import MapKit
import os

/// MKMapView wrapper. SwiftUI's `Map` can't draw tile overlays, and the public-lands
/// layer is a tile overlay, so the Explore map is UIKit underneath.
/// Also gives native pin clustering and long-press ("Can I camp here?").
struct CampMapView: UIViewRepresentable {
    let sites: [Site]
    var satellite: Bool
    var showPublicLands: Bool
    @Binding var recenter: MKCoordinateRegion?
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelect: (String) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.register(SiteMarkerView.self, forAnnotationViewWithReuseIdentifier: SiteMarkerView.reuseID)
        map.register(SiteClusterView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.setRegion(.init(center: .init(latitude: 37.6, longitude: -111.6),
                            span: .init(latitudeDelta: 6, longitudeDelta: 6)), animated: false)
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        // Tile overlays only render on flat terrain, so drop 3D elevation while the lands layer is on.
        // Only touch the configuration on a real change: reassigning it reloads the map and cancels tile loads.
        let style = MapStyleKey(satellite: satellite, lands: showPublicLands)
        if context.coordinator.appliedStyle != style {
            context.coordinator.appliedStyle = style
            let elevation: MKMapConfiguration.ElevationStyle = showPublicLands ? .flat : .realistic
            map.preferredConfiguration = satellite
                ? MKHybridMapConfiguration(elevationStyle: elevation)
                : MKStandardMapConfiguration(elevationStyle: elevation)
        }

        let hasLands = map.overlays.contains { $0 is PublicLandsOverlay }
        if showPublicLands && !hasLands {
            map.addOverlay(PublicLandsOverlay(), level: .aboveRoads)
        } else if !showPublicLands && hasLands {
            map.removeOverlays(map.overlays.filter { $0 is PublicLandsOverlay })
        }

        if let region = recenter {
            map.setRegion(region, animated: true)
            DispatchQueue.main.async { recenter = nil }
        }

        // Diff annotations by site id so pins that stay on screen don't flicker.
        let current = map.annotations.compactMap { $0 as? SiteAnnotation }
        let currentIDs = Set(current.map(\.site.id))
        let wantedIDs = Set(sites.map(\.id))
        map.removeAnnotations(current.filter { !wantedIDs.contains($0.site.id) })
        map.addAnnotations(sites.filter { !currentIDs.contains($0.id) }.map { SiteAnnotation($0) })
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CampMapView
        var appliedStyle: MapStyleKey?
        init(_ parent: CampMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation)
            }
            return mapView.dequeueReusableAnnotationView(withIdentifier: SiteMarkerView.reuseID, for: annotation)
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            } else if let a = annotation as? SiteAnnotation {
                mapView.deselectAnnotation(a, animated: false)
                parent.onSelect(a.site.id)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tiles)
                r.alpha = 0.55
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            parent.onLongPress(map.convert(g.location(in: map), toCoordinateFrom: map))
        }
    }
}

struct MapStyleKey: Equatable { let satellite: Bool; let lands: Bool }

// MARK: - Annotations

final class SiteAnnotation: NSObject, MKAnnotation {
    let site: Site
    var coordinate: CLLocationCoordinate2D { site.coordinate }
    var title: String? { site.name }
    init(_ site: Site) { self.site = site }
}

final class SiteMarkerView: MKMarkerAnnotationView {
    static let reuseID = "site"

    override var annotation: MKAnnotation? {
        didSet {
            guard let site = (annotation as? SiteAnnotation)?.site else { return }
            clusteringIdentifier = "sites"
            markerTintColor = UIColor(site.likelyFree ? Color.meadow : site.kind.color)
            glyphImage = UIImage(systemName: site.kind.symbol)
            titleVisibility = .adaptive
            displayPriority = site.likelyFree ? .defaultHigh : .defaultLow
        }
    }
}

final class SiteClusterView: MKMarkerAnnotationView {
    override var annotation: MKAnnotation? {
        didSet {
            guard let cluster = annotation as? MKClusterAnnotation else { return }
            markerTintColor = UIColor(Color.sunset)
            glyphText = cluster.memberAnnotations.count > 99 ? "99+" : "\(cluster.memberAnnotations.count)"
            displayPriority = .defaultHigh
        }
    }
}

// MARK: - Public lands

/// BLM national Surface Management Agency map (public domain): who manages each parcel.
/// Cached Web Mercator tiles, so it works as a plain tile overlay.
final class PublicLandsOverlay: MKTileOverlay {
    private static let cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 40 * 1024 * 1024
        return c
    }()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 150 << 20)
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
    private static let log = Logger(subsystem: "ezcamps", category: "PublicLands")

    init() {
        super.init(urlTemplate: PublicLandsService.base + "/tile/{z}/{y}/{x}")
        canReplaceMapContent = false
        minimumZ = 4
        maximumZ = 16
    }

    // Load tiles ourselves: MapKit's default loader kept cancelling this server's requests.
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = url(forTilePath: path)
        let key = url.absoluteString as NSString
        if let hit = Self.cache.object(forKey: key) { result(hit as Data, nil); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.assumesHTTP3Capable = false
        req.setValue("ezcamps-ios", forHTTPHeaderField: "User-Agent")
        Self.session.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, status == 200 {
                Self.cache.setObject(data as NSData, forKey: key, cost: data.count)
                result(data, nil)
            } else {
                Self.log.error("tile \(path.z)/\(path.x)/\(path.y) failed: \(status) \(String(describing: error))")
                result(nil, error)
            }
        }.resume()
    }
}
