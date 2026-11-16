import SwiftUI
import MapKit
import os

/// MKMapView wrapper. SwiftUI's `Map` can't draw tile overlays, and the public-lands
/// layer is a tile overlay, so the Explore map is UIKit underneath.
/// Also gives native pin clustering and long-press ("Can I camp here?").
/// Base map style for Explore.
enum MapBase: String, CaseIterable, Identifiable {
    case standard, satellite, topo
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .topo: "Topo"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map.fill"
        case .satellite: "globe.americas.fill"
        case .topo: "mountain.2.fill"
        }
    }
}

struct CampMapView: UIViewRepresentable {
    let sites: [Site]
    var base: MapBase
    var showPublicLands: Bool
    var showForestRoads = false
    var showWater = false
    @Binding var recenter: MKCoordinateRegion?
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onSelect: (String) -> Void
    var onLongPress: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        #if DEBUG
        // Screenshot aid: even turning the dot on for a moment asks for location.
        map.showsUserLocation = !UserDefaults.standard.bool(forKey: "debugNoLocation")
        #else
        map.showsUserLocation = true
        #endif
        map.showsCompass = true
        map.showsScale = true
        // Nature landmarks only (parks, beaches, trailheads, climbing, paddling); no shops or restaurants.
        map.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .nationalPark, .nationalMonument, .park, .beach, .landmark, .hiking,
            .rockClimbing, .kayaking, .fishing, .skiing, .marina,
        ])
        map.register(SiteMarkerView.self, forAnnotationViewWithReuseIdentifier: SiteMarkerView.reuseID)
        map.register(Site3DPinView.self, forAnnotationViewWithReuseIdentifier: Site3DPinView.reuseID)
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
        // Tile overlays only render on flat terrain, so drop 3D elevation while topo or lands is on.
        // Only touch the configuration and overlays on a real change: reassigning reloads the map
        // and cancels tile loads.
        let style = MapStyleKey(base: base, lands: showPublicLands, roads: showForestRoads, water: showWater)
        if context.coordinator.appliedStyle != style {
            context.coordinator.appliedStyle = style
            let flat = showPublicLands || showForestRoads || showWater || base == .topo
            let elevation: MKMapConfiguration.ElevationStyle = flat ? .flat : .realistic
            map.preferredConfiguration = base == .satellite
                ? MKHybridMapConfiguration(elevationStyle: elevation)
                : MKStandardMapConfiguration(elevationStyle: elevation)
            // Rebuild tile overlays in drawing order: topo underneath, public lands on top.
            map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
            if base == .topo { map.addOverlay(TopoOverlay(), level: .aboveRoads) }
            if showPublicLands { map.addOverlay(PublicLandsOverlay(), level: .aboveRoads) }
            if showWater { map.addOverlay(WaterOverlay(), level: .aboveRoads) }
            if showForestRoads { map.addOverlay(ForestRoadsOverlay(), level: .aboveLabels) }
        }

        if let region = recenter {
            if region.span.longitudeDelta > 30, map.bounds.width > 0 {
                // Continent scale: MapKit draws a globe here, so flat-map rect math over- or
                // under-shoots. Fit the width with camera altitude instead.
                map.setCamera(Self.camera(fittingWidthOf: region, in: map.bounds.size), animated: true)
            } else {
                map.setVisibleMapRect(Self.fittedRect(region, in: map.bounds.size, padding: Self.fitPadding),
                                      edgePadding: Self.fitPadding, animated: true)
            }
            DispatchQueue.main.async { recenter = nil }
        }

        // Diff annotations by site id so pins that stay on screen don't flicker.
        let current = map.annotations.compactMap { $0 as? SiteAnnotation }
        let currentIDs = Set(current.map(\.site.id))
        let wantedIDs = Set(sites.map(\.id))
        map.removeAnnotations(current.filter { !wantedIDs.contains($0.site.id) })
        map.addAnnotations(sites.filter { !currentIDs.contains($0.id) }.map { SiteAnnotation($0) })
    }

    /// Camera high enough that the region's full longitude span fits the screen width.
    /// Measured in MapKit (iOS 26): a 402×874 pt map at 8,000 km shows ~22.9° of longitude, and the
    /// visible width grows linearly with altitude and with the view's width-to-height ratio.
    static func camera(fittingWidthOf region: MKCoordinateRegion, in size: CGSize) -> MKMapCamera {
        let degreesPerMeter = 22.86 / 8_000_000 * (Double(size.width / size.height) / (402.0 / 874.0))
        let distance = region.span.longitudeDelta * 1.06 / degreesPerMeter  // 6% margin at the edges
        return MKMapCamera(lookingAtCenter: region.center, fromDistance: distance, pitch: 0, heading: 0)
    }

    /// Room for the search header and the status pill.
    static let fitPadding = UIEdgeInsets(top: 150, left: 12, bottom: 120, right: 12)

    /// The region as a map rect, grown (around its centre, in map space) to the screen's shape so
    /// MapKit shows all of it. setRegion alone fits the height on a portrait phone and crops the sides.
    static func fittedRect(_ region: MKCoordinateRegion, in size: CGSize, padding: UIEdgeInsets) -> MKMapRect {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                   longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                   longitude: region.center.longitude + region.span.longitudeDelta / 2))
        var rect = MKMapRect(x: min(nw.x, se.x), y: min(nw.y, se.y), width: abs(se.x - nw.x), height: abs(se.y - nw.y))
        let w = max(size.width - padding.left - padding.right, 1)
        let h = max(size.height - padding.top - padding.bottom, 1)
        let screenAspect = h / w
        if rect.size.height / rect.size.width < screenAspect {
            let grown = rect.size.width * screenAspect
            rect.origin.y -= (grown - rect.size.height) / 2
            rect.size.height = grown
        } else {
            let grown = rect.size.height / screenAspect
            rect.origin.x -= (grown - rect.size.width) / 2
            rect.size.width = grown
        }
        return rect
    }

    /// Narrower than this (degrees; ~30 mi across in the lower 48) pins switch from flat markers to 3D icons.
    /// Zoomed out there can be hundreds of pins, and full-colour art at that density is noise.
    static let detailSpan = 0.6

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CampMapView
        var appliedStyle: MapStyleKey?
        var showing3D = false
        init(_ parent: CampMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // Crossing the detail zoom: re-add the pins so each gets the right kind of view.
            let span = mapView.region.span
            let detailed = min(span.latitudeDelta, span.longitudeDelta) < CampMapView.detailSpan
            if detailed != showing3D {
                showing3D = detailed
                let pins = mapView.annotations.compactMap { $0 as? SiteAnnotation }
                mapView.removeAnnotations(pins)
                mapView.addAnnotations(pins)
            }
            // Can fire synchronously inside updateUIView (setRegion); SwiftUI drops state changes made
            // during a view update, so hand it over on the next run-loop pass.
            let region = mapView.region
            DispatchQueue.main.async { self.parent.onRegionChange(region) }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation)
            }
            let id = showing3D ? Site3DPinView.reuseID : SiteMarkerView.reuseID
            return mapView.dequeueReusableAnnotationView(withIdentifier: id, for: annotation)
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
                r.alpha = tiles is PublicLandsOverlay ? 0.55 : 1
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

struct MapStyleKey: Equatable { let base: MapBase; let lands: Bool; let roads: Bool; let water: Bool }

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

/// Zoomed-in pin: the site's 3D icon in a white bubble with a coloured ring (green when free) and a
/// small pointer at the exact spot. Images are rendered once per kind and colour, then reused.
final class Site3DPinView: MKAnnotationView {
    static let reuseID = "site3d"
    private static var cache: [String: UIImage] = [:]

    /// Site name under the bubble, like Apple Maps labels: small, bold, with a soft halo for contrast.
    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 2
        l.layer.shadowColor = UIColor.systemBackground.cgColor
        l.layer.shadowOpacity = 1
        l.layer.shadowRadius = 2
        l.layer.shadowOffset = .zero
        return l
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width: CGFloat = 110
        let fit = nameLabel.sizeThatFits(CGSize(width: width, height: 40))
        nameLabel.frame = CGRect(x: (bounds.width - fit.width) / 2, y: bounds.height, width: fit.width, height: fit.height)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        nameLabel.layer.shadowColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let site = (annotation as? SiteAnnotation)?.site else { return }
            clusteringIdentifier = "sites"
            image = Self.image(for: site)
            nameLabel.text = site.isNamed ? site.name : nil
            setNeedsLayout()
            centerOffset = CGPoint(x: 0, y: -image!.size.height / 2 + 2)  // pointer tip on the coordinate
            displayPriority = site.likelyFree ? .defaultHigh : .defaultLow
            collisionMode = .circle
            accessibilityLabel = "\(site.name), \(site.priceLabel)"
        }
    }

    private static func image(for site: Site) -> UIImage {
        let key = "\(site.kind.rawValue)-\(site.likelyFree)"
        if let hit = cache[key] { return hit }
        let ring = UIColor(site.likelyFree ? Color.meadow : site.kind.color)
        let bubble: CGFloat = 40, pointer: CGFloat = 7
        let size = CGSize(width: bubble + 6, height: bubble + pointer + 6)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            let rect = CGRect(x: 3, y: 2, width: bubble, height: bubble)
            g.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            // Pointer
            let tip = CGPoint(x: size.width / 2, y: rect.maxY + pointer)
            g.move(to: CGPoint(x: tip.x - 6, y: rect.maxY - 3))
            g.addLine(to: tip)
            g.addLine(to: CGPoint(x: tip.x + 6, y: rect.maxY - 3))
            g.closePath()
            ring.setFill()
            g.fillPath()
            // Ring and white bubble
            g.fillEllipse(in: rect)
            g.setShadow(offset: .zero, blur: 0)
            UIColor.white.setFill()
            g.fillEllipse(in: rect.insetBy(dx: 3, dy: 3))
            if let icon = UIImage(named: "e3d-\(site.kind.icon3D)") {
                icon.draw(in: rect.insetBy(dx: 7, dy: 7))
            }
        }
        cache[key] = img
        return img
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
        // Downloaded state packs work with no signal.
        if let saved = TileCache.data(z: path.z, x: path.x, y: path.y) { result(saved, nil); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.assumesHTTP3Capable = false
        req.setValue("ezcamp-ios", forHTTPHeaderField: "User-Agent")
        Self.session.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, status == 200 {
                Self.cache.setObject(data as NSData, forKey: key, cost: data.count)
                result(data, nil)
            } else if let enlarged = TileCache.overzoomed(z: path.z, x: path.x, y: path.y) {
                // Offline (or past the pack's zoom): enlarge the closest downloaded tile.
                result(enlarged, nil)
            } else {
                Self.log.error("tile \(path.z)/\(path.x)/\(path.y) failed: \(status) \(String(describing: error))")
                result(nil, error)
            }
        }.resume()
    }
}

// MARK: - Rivers and lakes

/// USGS National Hydrography Dataset, cached as a transparent overlay (public domain): streams,
/// rivers, lakes and reservoirs with names, drawn over any base map.
final class WaterOverlay: MKTileOverlay {
    static let base = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSHydroCached/MapServer"
    private static let cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 30 * 1024 * 1024
        return c
    }()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 10 << 20, diskCapacity: 100 << 20)
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    init() {
        super.init(urlTemplate: Self.base + "/tile/{z}/{y}/{x}")
        canReplaceMapContent = false
        minimumZ = 6
        maximumZ = 16
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = url(forTilePath: path)
        let key = url.absoluteString as NSString
        if let hit = Self.cache.object(forKey: key) { result(hit as Data, nil); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.assumesHTTP3Capable = false
        req.setValue("ezcamp-ios", forHTTPHeaderField: "User-Agent")
        Self.session.dataTask(with: req) { data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                Self.cache.setObject(data as NSData, forKey: key, cost: data.count)
                result(data, nil)
            } else {
                result(nil, error)
            }
        }.resume()
    }
}

// MARK: - Topo

/// USGS National Map topographic base map (public domain): contour lines, peaks with elevations,
/// streams and springs, falls, glaciers, forest roads and trails. Replaces Apple's base map.
final class TopoOverlay: MKTileOverlay {
    static let base = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer"
    private static let cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 200 << 20)
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    init() {
        super.init(urlTemplate: Self.base + "/tile/{z}/{y}/{x}")
        canReplaceMapContent = true
        maximumZ = 16  // USGS caches to 16; MapKit enlarges beyond that
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let url = url(forTilePath: path)
        let key = url.absoluteString as NSString
        if let hit = Self.cache.object(forKey: key) { result(hit as Data, nil); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.assumesHTTP3Capable = false
        req.setValue("ezcamp-ios", forHTTPHeaderField: "User-Agent")
        Self.session.dataTask(with: req) { data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                Self.cache.setObject(data as NSData, forKey: key, cost: data.count)
                result(data, nil)
            } else {
                result(nil, error)
            }
        }.resume()
    }
}
