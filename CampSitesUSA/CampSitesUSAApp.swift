import SwiftUI
import SwiftData

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
    var body: some View {
        TabView {
            Tab("Explore", systemImage: "map.fill") { ExploreView() }
            Tab("Trips", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") { TripsView() }
            Tab("Saved", systemImage: "heart.fill") { SavedView() }
        }
    }
}
