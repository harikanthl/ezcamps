import SwiftUI
import SwiftData
import CoreLocation
import os

@main
struct CampSitesUSAApp: App {
    @State private var store = SiteStore()
    @State private var location = LocationProvider()
    @State private var offline = OfflineStore()
    @State private var ai = AISettings()
    @State private var community = CommunityAccount()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(offline)
                .environment(ai)
                .environment(community)
                .tint(.sunset)
                .task { await store.load() }
        }
        .modelContainer(for: [SavedSite.self, Visit.self, Trip.self, TripStop.self])
    }
}

struct RootView: View {
    @State private var tab = "explore"
    @Environment(CommunityAccount.self) private var community
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @Environment(SiteStore.self) private var store
    @Environment(OfflineStore.self) private var offline
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        TabView(selection: $tab) {
            Tab("Explore", systemImage: "map.fill", value: "explore") { ExploreView() }
            Tab("Trips", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill", value: "trips") { TripsView() }
            Tab("Saved", systemImage: "heart.fill", value: "saved") { SavedView() }
        }
        // Shared ratings: drop the session if Apple ID access was revoked, then upload anything
        // rated while offline. Again whenever the app comes back to the foreground.
        .task {
            await community.checkAppleCredential()
            await community.sync(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await community.sync(context: modelContext) } }
        }
        #if DEBUG
        // Testing aids: `-debugDownloadState UT` downloads a pack; `-debugOfflineProbe YES` logs
        // offline land answers for known points (compare with the online check).
        .task {
            if let code = UserDefaults.standard.string(forKey: "debugDownloadState") { offline.download([code]) }
            if UserDefaults.standard.string(forKey: "debugAIPrompt") != nil { tab = "trips" }
            if DebugLaunch.isSet("debugSettings") { tab = "saved" }
            if UserDefaults.standard.bool(forKey: "debugOfflineProbe") {
                let log = Logger(subsystem: "ezcamps", category: "OfflineProbe")
                let points: [(String, Double, Double)] = [("BLM near Moab", 38.9, -110.5), ("Arches NP", 38.62, -109.62),
                    ("Manti-La Sal NF", 38.45, -109.25), ("Moab town", 38.573, -109.55), ("Navajo Nation", 37.05, -110.0)]
                for (label, lat, lon) in points {
                    let code = OfflineLand.agency(at: .init(latitude: lat, longitude: lon)) ?? "nil"
                    log.notice("probe \(label, privacy: .public) -> \(code, privacy: .public)")
                }
            }
        }
        // Screenshot/testing aid: `-debugPlanTrip YES` plans Moab → Old Faithful and opens Trips.
        .onChange(of: store.isLoaded) {
            guard store.isLoaded, DebugLaunch.flag("debugPlanTrip") else { return }
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
