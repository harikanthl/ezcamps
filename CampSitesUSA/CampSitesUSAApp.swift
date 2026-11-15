import SwiftUI
import SwiftData
import CoreLocation

@main
struct CampSitesUSAApp: App {
    @State private var store = SiteStore()
    @State private var location = LocationProvider()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .tint(.sunset)
                .task { await store.load() }
        }
        .modelContainer(for: [SavedSite.self, Visit.self, Trip.self, TripStop.self])
    }
}

struct RootView: View {
    @State private var tab = "explore"
    #if DEBUG
    @Environment(SiteStore.self) private var store
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        TabView(selection: $tab) {
            Tab("Explore", systemImage: "map.fill", value: "explore") { ExploreView() }
            Tab("Trips", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill", value: "trips") { TripsView() }
            Tab("Saved", systemImage: "heart.fill", value: "saved") { SavedView() }
        }
        #if DEBUG
        // Screenshot/testing aid: `-debugPlanTrip YES` plans Moab → Old Faithful and opens Trips.
        .onChange(of: store.isLoaded) {
            guard UserDefaults.standard.bool(forKey: "debugPlanTrip") else { return }
            Task {
                let from = CLLocationCoordinate2D(latitude: 38.5733, longitude: -109.5498)
                let to = CLLocationCoordinate2D(latitude: 44.4605, longitude: -110.8281)
                guard let route = await TripPlanner.route(from: from, to: to) else { return }
                let trip = Trip(name: "Moab → Yellowstone")
                trip.startName = "Moab, UT"; trip.startLat = from.latitude; trip.startLon = from.longitude
                trip.endName = "Old Faithful"; trip.endLat = to.latitude; trip.endLon = to.longitude
                trip.startDate = .now; trip.dailyMiles = 250
                context.insert(trip)
                for (i, site) in TripPlanner.suggestStops(on: route, dailyMiles: 250, preferFree: true, store: store).enumerated() {
                    let stop = TripStop(site: site, order: i)
                    stop.suggested = true
                    trip.stops.append(stop)
                }
                tab = "trips"
            }
        }
        #endif
    }
}
