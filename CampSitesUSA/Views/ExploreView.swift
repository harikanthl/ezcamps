import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(SiteStore.self) private var store
    @Environment(LocationProvider.self) private var location

    // Start over the Four Corners region where the bundled data lives.
    @State private var position: MapCameraPosition = .region(.init(
        center: .init(latitude: 37.6, longitude: -111.6),
        span: .init(latitudeDelta: 6, longitudeDelta: 6)))
    @State private var region: MKCoordinateRegion?
    @State private var filter = SiteFilter()
    @State private var visible: [Site] = []
    @State private var totalInView = 0
    @State private var selectedID: String?
    @State private var selectedSite: Site?
    @State private var satellite = false

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(visible) { site in
                Marker(site.name, systemImage: site.kind.symbol, coordinate: site.coordinate)
                    .tint(site.likelyFree ? Color.meadow : site.kind.color)
                    .tag(site.id)
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                            : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            region = ctx.region
            refresh()
        }
        .onChange(of: filter) { refresh() }
        .onChange(of: store.isLoaded) { refresh() }
        .onChange(of: selectedID) { _, id in
            if let id { selectedSite = store.site(id: id) }
        }
        .safeAreaInset(edge: .top) { header }
        .overlay(alignment: .bottom) { statusPill }
        .sheet(item: $selectedSite, onDismiss: { selectedID = nil }) { site in
            NavigationStack { SiteDetailView(site: site) }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(28)
        }
        .task { location.start() }
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
        .padding(.bottom, 12)
        .allowsHitTesting(false)
        .contentTransition(.numericText())
    }
}
