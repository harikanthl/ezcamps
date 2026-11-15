import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(SiteStore.self) private var store
    @Environment(LocationProvider.self) private var location

    @State private var region: MKCoordinateRegion?
    @State private var recenter: MKCoordinateRegion?
    @State private var filter = SiteFilter()
    @State private var visible: [Site] = []
    @State private var totalInView = 0
    @State private var selectedSite: Site?
    @State private var landQuery: LandQuery?
    @AppStorage("mapBase") private var base: MapBase = .standard
    @AppStorage("showPublicLands") private var showPublicLands = false
    @AppStorage("showForestRoads") private var showForestRoads = false

    var body: some View {
        CampMapView(
            sites: visible,
            base: base,
            showPublicLands: showPublicLands,
            showForestRoads: showForestRoads,
            recenter: $recenter,
            onRegionChange: { region = $0; refresh() },
            onSelect: { selectedSite = store.site(id: $0) },
            onLongPress: { landQuery = LandQuery(coordinate: $0) }
        )
        .ignoresSafeArea()
        .onChange(of: filter) { refresh() }
        .onChange(of: store.isLoaded) {
            refresh()
            #if DEBUG
            // Screenshot/testing aid: `-debugOpenSite <site id>` opens that site's card on launch.
            if let id = UserDefaults.standard.string(forKey: "debugOpenSite") { selectedSite = store.site(id: id) }
            #endif
        }
        .safeAreaInset(edge: .top) { header }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if base == .topo {
                    Text("Topo: USGS The National Map")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.regularMaterial, in: .capsule)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if showForestRoads {
                    ForestRoadsLegend(zoomedIn: (region?.span.latitudeDelta ?? 99) < 0.6)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                if showPublicLands {
                    PublicLandsLegend()
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                statusPill
            }
            .padding(.bottom, 12)
        }
        .overlay(alignment: .topTrailing) { locateButton }
        .sensoryFeedback(.impact(weight: .medium), trigger: landQuery?.id)
        .sheet(item: $selectedSite) { site in
            NavigationStack { SiteDetailView(site: site) }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(28)
        }
        .sheet(item: $landQuery) { q in
            LandCheckView(query: q)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(28)
        }
        .task {
            location.start()
            #if DEBUG
            // Testing aid: `-debugRegion "lat,lon,span"` opens the map there; `-debugRegion us` = the reset button.
            // `-debugLandCheck "lat,lon"` opens Can I camp here? there (stands in for a long-press).
            if let c = UserDefaults.standard.string(forKey: "debugLandCheck")?.split(separator: ",").compactMap({ Double($0) }), c.count == 2 {
                try? await Task.sleep(for: .seconds(2))
                landQuery = LandQuery(coordinate: .init(latitude: c[0], longitude: c[1]))
            }
            if UserDefaults.standard.string(forKey: "debugRegion") == "us" {
                try? await Task.sleep(for: .seconds(1.5))
                recenter = Self.usRegion
            }
            if let r = UserDefaults.standard.string(forKey: "debugRegion")?.split(separator: ",").compactMap({ Double($0) }), r.count == 3 {
                try? await Task.sleep(for: .seconds(1.5))  // like a real tap: after the map has its size
                recenter = MKCoordinateRegion(center: .init(latitude: r[0], longitude: r[1]),
                                              span: .init(latitudeDelta: r[2], longitudeDelta: r[2]))
            }
            #endif
        }
    }

    /// Whole lower 48, coast to coast (24.5–49.5°N, 125–66.5°W). CampMapView fits its width.
    static let usRegion = MKCoordinateRegion(center: .init(latitude: 38.0, longitude: -95.75),
                                             span: .init(latitudeDelta: 25, longitudeDelta: 58.5))

    private var locateButton: some View {
        VStack(spacing: 10) {
            mapButton(symbol: "location.fill", label: "Show my location") {
                guard let here = location.location?.coordinate else { location.start(); return }
                recenter = MKCoordinateRegion(center: here, span: .init(latitudeDelta: 0.6, longitudeDelta: 0.6))
            }
            mapButton(symbol: "map", label: "Show all of the US") {
                recenter = Self.usRegion
            }
        }
        .padding(.trailing)
        .padding(.top, 150)
    }

    private func mapButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.sky)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: .circle)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private func refresh() {
        guard let region else { return }
        let result = store.visible(in: region, filter: filter)
        visible = result.sites
        totalInView = result.total
    }

    // MARK: Header: search + filter chips

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.sunset)
                    TextField("Search campsites", text: $filter.query)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                    if !filter.query.isEmpty {
                        Button { filter.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.regularMaterial, in: .capsule)

                Menu {
                    Toggle(isOn: $showPublicLands.animation(.easeOut(duration: 0.2))) {
                        Label("Public lands", systemImage: "square.2.layers.3d.top.filled")
                    }
                    Toggle(isOn: $showForestRoads.animation(.easeOut(duration: 0.2))) {
                        Label("Forest roads (MVUM)", systemImage: "road.lanes")
                    }
                } label: {
                    let any = showPublicLands || showForestRoads
                    Image(systemName: "square.2.layers.3d.top.filled")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(any ? .white : Color.canyon)
                        .frame(width: 46, height: 46)
                        .background(any ? AnyShapeStyle(Color.canyon) : AnyShapeStyle(.regularMaterial), in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Map layers")

                Menu {
                    Picker("Map style", selection: $base) {
                        ForEach(MapBase.allCases) { b in
                            Label(b.label, systemImage: b.symbol).tag(b)
                        }
                    }
                } label: {
                    Image(systemName: base.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.sky, in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Map style: \(base.label)")
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(title: "Free", symbol: "dollarsign.circle.fill", tint: .meadow, isOn: filter.freeOnly) {
                        filter.freeOnly.toggle()
                    }
                    ForEach(Site.Kind.allCases, id: \.self) { kind in
                        Chip(title: kind.label, symbol: kind.symbol, tint: kind.color, isOn: filter.kinds.contains(kind)) {
                            filter.kinds.formSymmetricDifference([kind])
                        }
                    }
                    ForEach([Amenity.water, .toilets, .showers, .dump, .electric]) { a in
                        Chip(title: a.label, symbol: a.symbol, tint: .sky, isOn: filter.amenities.contains(a)) {
                            filter.amenities.formSymmetricDifference([a])
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Status

    private var statusPill: some View {
        Group {
            if !store.isLoaded {
                Label("Loading campsites…", systemImage: "hourglass")
            } else if filter.kinds.isEmpty {
                Label("Pick a site type to see campsites", systemImage: "line.3.horizontal.decrease.circle")
            } else if totalInView > visible.count {
                Label("Showing \(visible.count) of \(totalInView.formatted()). Zoom in for more", systemImage: "plus.magnifyingglass")
            } else {
                Label("\(totalInView.formatted()) campsites here", systemImage: "tent.2.fill")
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .allowsHitTesting(false)
        .contentTransition(.numericText())
    }
}
