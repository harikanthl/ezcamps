import SwiftUI
import SwiftData
import MapKit

// MARK: - Trips list

struct TripsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var planning = false
    @State private var path: [Trip] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("Plan a road trip", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .foregroundStyle(Color.dusk)
                    } description: {
                        Text("Tell us where you're starting and where you're headed. We'll map the drive and suggest a camp for each night, free ones first.")
                    } actions: {
                        Button {
                            planning = true
                        } label: {
                            Label("Plan a trip", systemImage: "map.fill").padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent).tint(.dusk).controlSize(.large)
                    }
                } else {
                    List {
                        ForEach(trips) { trip in
                            NavigationLink(value: trip) { TripCard(trip: trip) }
                        }
                        .onDelete { $0.map { trips[$0] }.forEach(context.delete) }
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .toolbar {
                Button("Plan a trip", systemImage: "plus") { planning = true }
            }
            .sheet(isPresented: $planning) {
                PlanTripView { trip in path.append(trip) }
            }
            #if DEBUG
            .onAppear(perform: debugOpen)
            .onChange(of: trips.count, debugOpen)
            #endif
        }
    }
}

#if DEBUG
extension TripsView {
    func debugOpen() {
        if UserDefaults.standard.bool(forKey: "debugPlanTrip"), let t = trips.first, path.isEmpty { path = [t] }
    }
}
#endif

private struct TripCard: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.dusk, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name).font(.headline).lineLimit(1)
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        var parts = ["\(trip.stops.count) camp\(trip.stops.count == 1 ? "" : "s")",
                     "\(trip.totalNights) night\(trip.totalNights == 1 ? "" : "s")"]
        if let d = trip.startDate { parts.append("starts \(d.formatted(.dateTime.month(.abbreviated).day()))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Plan a trip

struct PlanTripView: View {
    var onCreate: (Trip) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SiteStore.self) private var store
    @Environment(LocationProvider.self) private var location

    @State private var from: TripPlace?          // nil = current location
    @State private var to: TripPlace?
    @State private var startDate = Date.now
    @State private var dailyMiles = 250
    @State private var preferFree = true
    @State private var picking: Field?
    @State private var working = false
    @State private var error: String?

    enum Field: String, Identifiable { case from, to; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    placeRow(label: "From", symbol: "location.fill", color: .meadow,
                             value: from?.name ?? "Current location", placeholder: false) { picking = .from }
                    placeRow(label: "To", symbol: "flag.checkered", color: .berry,
                             value: to?.name ?? "Choose a destination", placeholder: to == nil) { picking = .to }
                }

                Section("When") {
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                }

                Section {
                    Picker("Driving per day", selection: $dailyMiles) {
                        ForEach([150, 250, 350, 500], id: \.self) { Text("\($0) mi").tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Driving per day")
                } footer: {
                    Text("We'll suggest a camp near the end of each day's drive.")
                }

                Section {
                    Toggle("Prefer free camps", isOn: $preferFree).tint(.meadow)
                } footer: {
                    Text("Free and likely-free sites rank first. Spots without a name or details are never suggested.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.berry)
                    }
                }
            }
            .navigationTitle("Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { planButton }
            .sheet(item: $picking) { field in
                PlaceSearchView(title: field == .from ? "Starting from" : "Going to",
                                allowCurrentLocation: field == .from) { place in
                    if field == .from { from = place } else { to = place }
                    error = nil
                }
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func placeRow(label: String, symbol: String, color: Color, value: String,
                          placeholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(value).foregroundStyle(placeholder ? .secondary : .primary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var planButton: some View {
        Button {
            Task { await plan() }
        } label: {
            HStack(spacing: 8) {
                if working {
                    ProgressView().tint(.white)
                    Text("Finding camps along your route…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Plan my trip")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(to == nil ? AnyShapeStyle(Color.secondary.opacity(0.4)) : AnyShapeStyle(Color.sunset),
                        in: .rect(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(to == nil || working)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func plan() async {
        guard let to else { return }
        guard let start = from?.coordinate ?? location.location?.coordinate else {
            error = "Turn on location, or choose where you're starting from."
            return
        }
        working = true
        defer { working = false }
        guard let route = await TripPlanner.route(from: start, to: to.coordinate) else {
            error = "Couldn't find a driving route between those places."
            return
        }
        let trip = Trip(name: "\(from?.name ?? "My location") → \(to.name)")
        trip.startName = from?.name ?? "My location"
        trip.startLat = start.latitude
        trip.startLon = start.longitude
        trip.endName = to.name
        trip.endLat = to.coordinate.latitude
        trip.endLon = to.coordinate.longitude
        trip.startDate = startDate
        trip.dailyMiles = dailyMiles
        trip.preferFree = preferFree
        context.insert(trip)
        for (i, site) in TripPlanner.suggestStops(on: route, dailyMiles: dailyMiles, preferFree: preferFree, store: store).enumerated() {
            let stop = TripStop(site: site, order: i)
            stop.suggested = true
            trip.stops.append(stop)
        }
        dismiss()
        onCreate(trip)
    }
}

// MARK: - Place search

struct PlaceSearchView: View {
    let title: String
    let allowCurrentLocation: Bool
    /// nil means "current location".
    let onPick: (TripPlace?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @State private var resolving: MKLocalSearchCompletion?

    var body: some View {
        NavigationStack {
            List {
                if allowCurrentLocation && search.query.isEmpty {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        Label("Current location", systemImage: "location.fill").foregroundStyle(Color.sky)
                    }
                }
                ForEach(search.results, id: \.self) { c in
                    Button {
                        Task {
                            resolving = c
                            if let place = await search.resolve(c) {
                                onPick(place)
                                dismiss()
                            }
                            resolving = nil
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).foregroundStyle(.primary)
                                if !c.subtitle.isEmpty {
                                    Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if resolving == c { ProgressView() }
                        }
                    }
                }
            }
            .overlay {
                if search.query.isEmpty && !allowCurrentLocation {
                    ContentUnavailableView("Where to?", systemImage: "magnifyingglass",
                                           description: Text("Search a city, national park or address."))
                }
            }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "City, park or address")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Trip detail (day-by-day itinerary)

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(SiteStore.self) private var store
    @State private var legs: [MKRoute?] = []
    @State private var routing = false
    @State private var position: MapCameraPosition = .automatic
    @State private var openSite: Site?
    @State private var swapping: TripStop?
    @State private var addingStop = false
    @State private var renaming = false
    @State private var replanning = false
    @State private var editMode: EditMode = .inactive

    private let legColors: [Color] = [.sunset, .dusk, .sky, .berry, .meadow, .canyon]

    var body: some View {
        List {
            Section {
                map
                    .frame(height: 260)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 12) {
                    stat(value: totalDistance, label: "Driving", color: .sunset)
                    stat(value: totalTime, label: "Drive time", color: .dusk)
                    stat(value: "\(trip.totalNights)", label: "Nights", color: .meadow)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(.init())
            }

            if trip.waypoints.count < 2 {
                Section {
                    Label("Add at least two camps to see the drive between them.", systemImage: "info.circle.fill")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Section {
                if let name = trip.startName {
                    endpointRow(title: name, caption: dayLabel(1).map { "Start · \($0)" } ?? "Start",
                                symbol: "location.fill", color: .meadow)
                }
                ForEach(Array(trip.orderedStops.enumerated()), id: \.element.id) { i, stop in
                    stopRow(stop, index: i)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) { remove(stop) }
                        }
                }
                .onMove(perform: move)
                if trip.endName != nil && legIsSlow(trip.orderedStops.count) {
                    slowWarning(trip.orderedStops.count).moveDisabled(true).deleteDisabled(true)
                }
                if let name = trip.endName {
                    endpointRow(title: name, subtitle: legText(trip.orderedStops.count),
                                caption: dayLabel(1 + trip.totalNights).map { "Arrive · \($0)" } ?? "Arrive",
                                symbol: "flag.checkered", color: .berry)
                }
                Button {
                    addingStop = true
                } label: {
                    Label("Add a camp", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
                }
                .tint(.sunset)
            } header: {
                Text("Itinerary")
            } footer: {
                Text("Most BLM and National Forest land limits stays to 14 days in one spot. Suggested camps are picked from open data. Check each one before you go.")
            }
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add a camp", systemImage: "plus") { addingStop = true }
                    if trip.start != nil && trip.end != nil {
                        Button("Re-suggest camps", systemImage: "sparkles") { Task { await resuggest() } }
                    }
                    Button("Reorder camps", systemImage: "arrow.up.arrow.down") { editMode = .active }
                    Button("Rename", systemImage: "pencil") { renaming = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .opacity(editMode.isEditing ? 0 : 1)
                .overlay {
                    if editMode.isEditing { Button("Done") { editMode = .inactive }.fontWeight(.semibold) }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .task(id: trip.waypoints.map { "\($0.latitude),\($0.longitude)" }) { await buildRoutes() }
        .sheet(item: $openSite) { site in
            NavigationStack { SiteDetailView(site: site) }.presentationDetents([.medium, .large])
        }
        .sheet(item: $swapping) { stop in
            SwapStopView(trip: trip, stop: stop)
        }
        .sheet(isPresented: $addingStop) {
            AddStopView(trip: trip, routes: legs.compactMap { $0 })
        }
        .alert("Rename trip", isPresented: $renaming) {
            TextField("Trip name", text: $trip.name)
            Button("Done") {}
        }
        .overlay {
            if replanning {
                ProgressView("Finding camps…").padding().background(.regularMaterial, in: .rect(cornerRadius: 14))
            }
        }
    }

    // MARK: Map

    private var map: some View {
        Map(position: $position) {
            if let s = trip.start {
                Marker(trip.startName ?? "Start", systemImage: "location.fill", coordinate: s).tint(Color.meadow)
            }
            ForEach(Array(trip.orderedStops.enumerated()), id: \.element.id) { i, stop in
                Marker("\(i + 1). \(stop.name)", monogram: Text("\(i + 1)"), coordinate: stop.coordinate)
                    .tint(Color.sunset)
            }
            if let e = trip.end {
                Marker(trip.endName ?? "Destination", systemImage: "flag.checkered", coordinate: e).tint(Color.berry)
            }
            ForEach(Array(legs.enumerated()), id: \.offset) { i, route in
                if let route {
                    MapPolyline(route.polyline)
                        .stroke(legColors[i % legColors.count], style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if routing { ProgressView().padding(8).background(.regularMaterial, in: .circle).padding(8) }
        }
    }

    // MARK: Rows

    private func stopRow(_ stop: TripStop, index i: Int) -> some View {
        let site = store.site(id: stop.siteID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let day = dayLabel(arrivalDay(of: i)) {
                    Text("Day \(arrivalDay(of: i)) · \(day)").font(.caption.weight(.bold)).foregroundStyle(Color.dusk)
                }
                Spacer()
                if let leg = legText(i) {
                    Label(leg, systemImage: "car.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            if legIsSlow(i) { slowWarning(i) }
            HStack(alignment: .top, spacing: 12) {
                Text("\(i + 1)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.sunset, in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Button { openSite = site } label: {
                        Text(stop.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 6) {
                        if let site {
                            Text(site.priceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(site.likelyFree ? Color.meadow : .secondary)
                            Text("· \(site.kind.label)").font(.caption).foregroundStyle(.secondary)
                        }
                        if stop.suggested {
                            Text("Suggested")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.dusk)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.dusk.opacity(0.12), in: .capsule)
                        }
                    }
                }
            }
            HStack {
                Stepper(value: Binding(get: { stop.nights }, set: { stop.nights = $0; stop.suggested = false }), in: 0...14) {
                    Text(stop.nights == 0 ? "Pass through" : "\(stop.nights) night\(stop.nights == 1 ? "" : "s")")
                        .font(.subheadline)
                }
                .fixedSize()
                Spacer()
                Button {
                    swapping = stop
                } label: {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(.dusk).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func endpointRow(title: String, subtitle: String? = nil, caption: String,
                             symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption).font(.caption.weight(.bold)).foregroundStyle(color)
                Text(title).font(.body.weight(.semibold))
            }
            Spacer()
            if let subtitle {
                Label(subtitle, systemImage: "car.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .moveDisabled(true)
        .deleteDisabled(true)
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

    // MARK: Days and legs

    /// Day you arrive at stop i: everyone drives on day 1, then each night pushes the next drive a day.
    private func arrivalDay(of i: Int) -> Int {
        1 + trip.orderedStops.prefix(i).map(\.nights).reduce(0, +)
    }

    private func dayLabel(_ day: Int) -> String? {
        guard let start = trip.startDate,
              let d = Calendar.current.date(byAdding: .day, value: day - 1, to: start) else { return nil }
        return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// Drive that arrives at stop `i` (or at the destination when i == stops.count).
    private func legText(_ i: Int) -> String? {
        let index = trip.start != nil ? i : i - 1
        guard index >= 0, index < legs.count, let route = legs[index] else { return nil }
        let miles = Measurement(value: route.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        let time = Duration.seconds(route.expectedTravelTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
        return "\(miles) · \(time)"
    }

    /// MapKit sometimes routes around seasonal closures (e.g. Yellowstone in winter). A leg that
    /// averages under 20 mph is worth a warning rather than a silently huge drive time.
    private func legIsSlow(_ i: Int) -> Bool {
        let index = trip.start != nil ? i : i - 1
        guard index >= 0, index < legs.count, let route = legs[index], route.expectedTravelTime > 1800 else { return false }
        let mph = (route.distance / TripPlanner.metersPerMile) / (route.expectedTravelTime / 3600)
        return mph < 20
    }

    private func slowWarning(_ i: Int) -> some View {
        Label("Slow or seasonal road on this drive. Check road conditions.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.canyon)
    }

    private var totalDistance: String {
        let routes = legs.compactMap { $0 }
        return routes.isEmpty ? "–" : Measurement(value: routes.map(\.distance).reduce(0, +), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private var totalTime: String {
        let routes = legs.compactMap { $0 }
        return routes.isEmpty ? "–" : Duration.seconds(routes.map(\.expectedTravelTime).reduce(0, +))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
    }

    // MARK: Actions

    private func move(from: IndexSet, to: Int) {
        var stops = trip.orderedStops
        stops.move(fromOffsets: from, toOffset: to)
        for (i, s) in stops.enumerated() { s.order = i }
    }

    private func remove(_ stop: TripStop) {
        trip.stops.removeAll { $0.id == stop.id }
        trip.renumber()
    }

    private func buildRoutes() async {
        routing = true
        defer { routing = false }
        legs = await TripPlanner.legs(through: trip.waypoints)
    }

    /// Replace the planner's picks (keeping camps the user chose) with fresh suggestions.
    private func resuggest() async {
        guard let s = trip.start, let e = trip.end else { return }
        replanning = true
        defer { replanning = false }
        guard let route = await TripPlanner.route(from: s, to: e) else { return }
        trip.stops.removeAll { $0.suggested }
        trip.renumber()
        for site in TripPlanner.suggestStops(on: route, dailyMiles: trip.dailyMiles, preferFree: trip.preferFree, store: store) {
            TripPlanner.insert(site, into: trip, suggested: true)
        }
    }
}

// MARK: - Swap a stop

struct SwapStopView: View {
    let trip: Trip
    let stop: TripStop
    @Environment(SiteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var options: [Site] {
        let used = Set(trip.stops.map(\.siteID))
        return Array(TripPlanner.candidates(near: stop.coordinate, in: store, radius: 25,
                                            preferFree: trip.preferFree, excluding: used).prefix(25))
    }

    var body: some View {
        NavigationStack {
            List {
                if stop.suggested {
                    Section {
                        Button {
                            stop.suggested = false
                            dismiss()
                        } label: {
                            Label("Keep \(stop.name)", systemImage: "checkmark.circle.fill").foregroundStyle(Color.meadow)
                        }
                    }
                }
                Section {
                    ForEach(options) { site in
                        Button {
                            stop.siteID = site.id
                            stop.name = site.name
                            stop.lat = site.lat
                            stop.lon = site.lon
                            stop.suggested = false
                            dismiss()
                        } label: {
                            SiteOptionRow(site: site, detail: "\(TripPlanner.miles(site.coordinate, stop.coordinate).formatted(.number.precision(.fractionLength(1)))) mi from current pick")
                        }
                    }
                } header: {
                    Text("Other camps nearby")
                } footer: {
                    Text(trip.preferFree ? "Free and well-described camps first." : "Best-described camps first.")
                }
            }
            .overlay {
                if options.isEmpty {
                    ContentUnavailableView("No other camps nearby", systemImage: "tent",
                                           description: Text("Try adding a camp by name instead."))
                }
            }
            .navigationTitle("Swap camp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add a stop

struct AddStopView: View {
    let trip: Trip
    let routes: [MKRoute]
    @Environment(SiteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var along: [Site] = []

    private var matches: [Site] {
        guard query.count >= 2 else { return [] }
        return Array(store.sites.lazy.filter { !$0.isBare && $0.name.localizedCaseInsensitiveContains(query) }.prefix(50))
    }

    var body: some View {
        NavigationStack {
            List {
                if query.count >= 2 {
                    ForEach(matches) { site in row(site, detail: site.state) }
                } else if !along.isEmpty {
                    Section("Along your route") {
                        ForEach(along) { site in row(site, detail: site.state) }
                    }
                }
            }
            .overlay {
                if query.count >= 2 && matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if query.count < 2 && along.isEmpty {
                    ContentUnavailableView("Search for a camp", systemImage: "magnifyingglass",
                                           description: Text("Type a campground name."))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Campground name")
            .navigationTitle("Add a camp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { along = TripPlanner.sitesAlong(routes, in: store) }
        }
    }

    private func row(_ site: Site, detail: String) -> some View {
        Button {
            TripPlanner.insert(site, into: trip)
            dismiss()
        } label: {
            SiteOptionRow(site: site, detail: detail)
        }
        .disabled(trip.stops.contains { $0.siteID == site.id })
    }
}

/// Compact campsite row used in trip pickers.
struct SiteOptionRow: View {
    let site: Site
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: site.kind.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(site.likelyFree ? Color.meadow : site.kind.color, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(site.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text("\(site.priceLabel) · \(detail)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
