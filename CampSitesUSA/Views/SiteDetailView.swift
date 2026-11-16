import SwiftUI
import SwiftData
import MapKit

struct SiteDetailView: View {
    let site: Site

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var saved: [SavedSite]
    @Query private var visits: [Visit]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]
    @State private var showingRate = false
    @State private var showingNewTrip = false
    @State private var community: SiteCommunity?
    @State private var communityFailed = false
    @Environment(CommunityAccount.self) private var account

    init(site: Site) {
        self.site = site
        let id = site.id
        _saved = Query(filter: #Predicate<SavedSite> { $0.siteID == id })
        _visits = Query(filter: #Predicate<Visit> { $0.siteID == id }, sort: \Visit.date, order: .reverse)
    }

    private var isSaved: Bool { !saved.isEmpty }
    private var averageRating: Double? {
        visits.isEmpty ? nil : Double(visits.map(\.rating).reduce(0, +)) / Double(visits.count)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if site.isBare && visits.isEmpty { bareNote }
                if !site.amenities.isEmpty { amenities }
                NightConditionsSection(coordinate: site.coordinate, site: site)
                SafetySection(site: site, community: community).id("safety")
                CellSignalSection(site: site, visits: visits)
                if let d = site.description, !d.isEmpty { about(d) }
                NearbyActivitiesSection(site: site)
                CommunityRatingsSection(site: site, data: community, failed: communityFailed) { await loadCommunity() }
                    .id("community")
                ratingsSection
                infoSection
            }
            .padding()
        }
        #if DEBUG
        // Screenshot aid: `-debugSiteSection community` scrolls the card to that section.
        .task {
            guard let id = DebugLaunch.string("debugSiteSection") else { return }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
        #endif
        }
        .background(alignment: .top) {
            LinearGradient(colors: [site.kind.color.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .ignoresSafeArea()
        }
        .task(id: "\(site.id)#\(account.revision)") { await loadCommunity() }
        .sheet(isPresented: $showingRate) {
            NavigationStack { RateVisitView(site: site) }
        }
        .alert("New trip", isPresented: $showingNewTrip) { NewTripAlert(site: site) }
        .sensoryFeedback(.success, trigger: isSaved) { _, new in new }
    }

    // MARK: Sections

    /// Bare OpenStreetMap points have a location and nothing else. Say so plainly rather than
    /// dressing them up: trust comes from real details and verified visits.
    private var bareNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No details yet", systemImage: "questionmark.circle.fill")
                .font(.headline).foregroundStyle(Color.canyon)
            Text("Someone marked a campsite here on OpenStreetMap, but there's no name, fee or amenity info. Long-press the map to check who manages the land, and if you camp here, rate it so the next camper knows what to expect.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.canyon.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Badge(text: site.kind.label, symbol: site.kind.symbol, color: site.kind.color)
                Badge(text: site.priceLabel, symbol: "dollarsign.circle.fill",
                      color: site.likelyFree ? .meadow : .secondary)
                if site.reservable { Badge(text: "Reservable", symbol: "calendar", color: .dusk) }
            }
            Text(site.name).font(.title2.weight(.bold))
            HStack(spacing: 6) {
                if let avg = averageRating {
                    StarRatingView(rating: avg)
                    Text("\(avg, specifier: "%.1f") · your \(visits.count) visit\(visits.count == 1 ? "" : "s")")
                } else {
                    Text("Not rated yet")
                }
                if let agency = site.agency { Text("· \(agency)").lineLimit(1) }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            ActionTile(title: "Directions", symbol: "car.fill", color: .sunset, filled: true) {
                let item = MKMapItem(location: CLLocation(latitude: site.lat, longitude: site.lon), address: nil)
                item.name = site.name
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            }
            ActionTile(title: isSaved ? "Saved" : "Save", symbol: isSaved ? "heart.fill" : "heart",
                       color: .berry, filled: isSaved) { toggleSave() }
            ActionTile(title: "Rate", symbol: "star.fill", color: .sunshine) { showingRate = true }
            Menu {
                ForEach(trips) { trip in
                    Button(trip.name) { add(to: trip) }
                }
                Divider()
                Button("New trip…", systemImage: "plus") { showingNewTrip = true }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill").font(.title3.weight(.semibold))
                    Text("Add to trip").font(.caption.weight(.semibold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(Color.dusk)
                .background(Color.dusk.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
        }
    }

    private var amenities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amenities").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(site.amenities.compactMap(Amenity.init(rawValue:))) { a in
                    Label(a.label, systemImage: a.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.sky)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sky.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func about(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About").font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var ratingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your visits").font(.headline)
                Spacer()
                Button("Log a visit", systemImage: "plus.circle.fill") { showingRate = true }
                    .font(.subheadline.weight(.semibold))
                    .tint(.sunset)
            }
            if visits.isEmpty {
                Text("Stayed here? Rate it. Ratings logged on-site get a **Verified visit** badge so other campers can trust them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(visits) { VisitRow(visit: $0) }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").font(.headline)
            if let hours = site.openingHours { LabeledContent("Season / hours", value: hours) }
            if let stay = site.stayLimit { LabeledContent("Stay limit", value: stay) }
            if let len = site.maxVehicleLength { LabeledContent("Max vehicle", value: "\(Int(len)) ft") }
            if let phone = site.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                LabeledContent("Phone") { Link(phone, destination: url) }
            }
            if let s = site.url, let url = URL.web(s) {
                LabeledContent("Website") { Link(url.host() ?? s, destination: url).lineLimit(1) }
            }
            LabeledContent("Coordinates") {
                Text("\(site.lat, specifier: "%.5f"), \(site.lon, specifier: "%.5f")").textSelection(.enabled)
            }
            LabeledContent("Source", value: site.source.label)
            Text("Always check local rules, closures and fire restrictions before camping.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
        }
        .font(.subheadline)
    }

    // MARK: Actions

    /// Shared ratings for this site, used by "From other campers" and the Safety section.
    private func loadCommunity() async {
        do {
            let d = try await RatingsAPI.site(site.id, token: account.token)
            guard !Task.isCancelled else { return }
            community = d
            communityFailed = false
        } catch {
            if !Task.isCancelled && community == nil { communityFailed = true }
        }
    }

    private func toggleSave() {
        if let s = saved.first { context.delete(s) } else { context.insert(SavedSite(site: site)) }
    }

    private func add(to trip: Trip) {
        // Goes where it adds the least detour (before the destination on planned trips).
        TripPlanner.insert(site, into: trip)
    }
}

/// Text-field alert that creates a trip and drops the current site into it.
private struct NewTripAlert: View {
    let site: Site
    @Environment(\.modelContext) private var context
    @State private var name = ""

    var body: some View {
        TextField("Trip name", text: $name)
        Button("Create") {
            let trip = Trip(name: name.isEmpty ? "My trip" : name)
            context.insert(trip)
            trip.stops.append(TripStop(site: site, order: 0))
        }
        Button("Cancel", role: .cancel) {}
    }
}

struct VisitRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StarRatingView(rating: Double(visit.rating))
                if visit.verified {
                    Label("Verified visit", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.meadow)
                }
                Spacer()
                Text(visit.date, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
            }
            if !visit.tags.isEmpty {
                Text(visit.tags.joined(separator: " · ")).font(.caption.weight(.medium)).foregroundStyle(Color.sunset)
            }
            if !visit.note.isEmpty { Text(visit.note).font(.subheadline) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14, style: .continuous))
    }
}
