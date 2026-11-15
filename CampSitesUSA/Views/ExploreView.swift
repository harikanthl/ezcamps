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
    @State private var satellite = false
    @AppStorage("showPublicLands") private var showPublicLands = false

    var body: some View {
        CampMapView(
            sites: visible,
            satellite: satellite,
            showPublicLands: showPublicLands,
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
        .task { location.start() }
    }

    private var locateButton: some View {
        Button {
            guard let here = location.location?.coordinate else { location.start(); return }
            recenter = MKCoordinateRegion(center: here, span: .init(latitudeDelta: 0.6, longitudeDelta: 0.6))
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.sky)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: .circle)
        }
        .buttonStyle(.pressable)
        .padding(.trailing)
        .padding(.top, 150)
        .accessibilityLabel("Show my location")
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

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showPublicLands.toggle() }
                } label: {
                    Image(systemName: "square.2.layers.3d.top.filled")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(showPublicLands ? .white : Color.canyon)
                        .frame(width: 46, height: 46)
                        .background(showPublicLands ? AnyShapeStyle(Color.canyon) : AnyShapeStyle(.regularMaterial), in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(showPublicLands ? "Hide public lands" : "Show public lands")
                .accessibilityAddTraits(showPublicLands ? .isSelected : [])

                Button { satellite.toggle() } label: {
                    Image(systemName: satellite ? "map.fill" : "globe.americas.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.sky, in: .circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(satellite ? "Standard map" : "Satellite map")
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
