import SwiftUI
import SwiftData
import MapKit

struct TripsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("Plan your first trip", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .foregroundStyle(Color.dusk)
                    } description: {
                        Text("Open any campsite and tap **Add to trip** to start an itinerary with driving routes.")
                    } actions: {
                        Button("New trip") { showingNew = true }.buttonStyle(.borderedProminent).tint(.dusk)
                    }
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(trip.name).font(.headline)
                                    Text("\(trip.stops.count) stop\(trip.stops.count == 1 ? "" : "s") · \(trip.stops.map(\.nights).reduce(0, +)) nights")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { $0.map { trips[$0] }.forEach(context.delete) }
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .toolbar {
                Button("New trip", systemImage: "plus") { showingNew = true }
            }
            .alert("New trip", isPresented: $showingNew) {
                TextField("Trip name", text: $newName)
                Button("Create") {
                    context.insert(Trip(name: newName.isEmpty ? "My trip" : newName))
                    newName = ""
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
        }
    }
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(SiteStore.self) private var store
    @State private var routes: [MKRoute] = []
    @State private var routing = false
    @State private var position: MapCameraPosition = .automatic
    @State private var openSite: Site?

    private let legColors: [Color] = [.sunset, .dusk, .sky, .berry, .meadow, .canyon]

    var body: some View {
        List {
            Section {
                Map(position: $position) {
                    ForEach(Array(trip.orderedStops.enumerated()), id: \.element.id) { i, stop in
                        Marker("\(i + 1). \(stop.name)", monogram: Text("\(i + 1)"), coordinate: stop.coordinate)
                            .tint(Color.sunset)
                    }
                    ForEach(Array(routes.enumerated()), id: \.offset) { i, route in
                        MapPolyline(route.polyline)
                            .stroke(legColors[i % legColors.count], style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 12) {
                    stat(value: totalDistance, label: "Driving", color: .sunset)
                    stat(value: totalTime, label: "Drive time", color: .dusk)
                    stat(value: "\(trip.stops.map(\.nights).reduce(0, +))", label: "Nights", color: .meadow)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }

            Section("Stops") {
                ForEach(trip.orderedStops) { stop in
                    HStack {
                        Button {
                            openSite = store.site(id: stop.siteID)
                        } label: {
                            Text(stop.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                        }
                        Spacer()
                        Stepper("\(stop.nights) night\(stop.nights == 1 ? "" : "s")", value: Binding(
                            get: { stop.nights }, set: { stop.nights = $0 }), in: 0...14)
                            .fixedSize()
                            .font(.subheadline)
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            }

            if trip.orderedStops.contains(where: { $0.nights > 14 }) == false && trip.stops.count > 0 {
                Section {
                    Label("Most BLM and National Forest land limits stays to 14 days in one spot.", systemImage: "info.circle.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(trip.name)
        .toolbar { EditButton() }
        .overlay { if routing { ProgressView().controlSize(.large) } }
        .task(id: trip.orderedStops.map(\.siteID)) { await buildRoutes() }
        .sheet(item: $openSite) { site in
            NavigationStack { SiteDetailView(site: site) }.presentationDetents([.medium, .large])
        }
    }

    private func stat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var totalDistance: String {
        let meters = routes.map(\.distance).reduce(0, +)
        return routes.isEmpty ? "–" : Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private var totalTime: String {
        let t = routes.map(\.expectedTravelTime).reduce(0, +)
        return routes.isEmpty ? "–" : Duration.seconds(t).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }

    private func move(from: IndexSet, to: Int) {
        var stops = trip.orderedStops
        stops.move(fromOffsets: from, toOffset: to)
        for (i, s) in stops.enumerated() { s.order = i }
    }

    private func delete(_ offsets: IndexSet) {
        let stops = trip.orderedStops
        for i in offsets { trip.stops.removeAll { $0.id == stops[i].id } }
        for (i, s) in trip.orderedStops.enumerated() { s.order = i }
    }

    private func buildRoutes() async {
        let stops = trip.orderedStops
        guard stops.count >= 2 else { routes = []; return }
        routing = true
        defer { routing = false }
        var result: [MKRoute] = []
        for (a, b) in zip(stops, stops.dropFirst()) {
            let req = MKDirections.Request()
            req.source = MKMapItem(location: CLLocation(latitude: a.lat, longitude: a.lon), address: nil)
            req.destination = MKMapItem(location: CLLocation(latitude: b.lat, longitude: b.lon), address: nil)
            req.transportType = .automobile
            if let route = try? await MKDirections(request: req).calculate().routes.first {
                result.append(route)
            }
        }
        routes = result
    }
}
