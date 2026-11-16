import SwiftUI
import SwiftData

struct SavedView: View {
    enum Segment: String, CaseIterable { case saved = "Saved", visits = "My visits" }

    @Environment(\.modelContext) private var context
    @Environment(SiteStore.self) private var store
    @Environment(CommunityAccount.self) private var community
    @Query(sort: \SavedSite.savedAt, order: .reverse) private var saved: [SavedSite]
    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @State private var segment = Segment.saved
    @State private var openSite: Site?

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(.init())

                switch segment {
                case .saved: savedList
                case .visits: visitList
                }
            }
            .navigationTitle(segment.rawValue)
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                if FeatureFlags.offlinePacks {
                    NavigationLink {
                        OfflineMapsView()
                    } label: {
                        Label("Offline maps", systemImage: "arrow.down.circle")
                    }
                }
            }
            .sheet(item: $openSite) { site in
                NavigationStack { SiteDetailView(site: site) }.presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder private var savedList: some View {
        if saved.isEmpty {
            ContentUnavailableView("No saved spots yet", systemImage: "heart",
                                   description: Text("Tap the heart on any campsite to keep it here, even offline."))
                .foregroundStyle(Color.berry)
                .listRowBackground(Color.clear)
        }
        ForEach(saved) { s in
            Button { openSite = store.site(id: s.siteID) } label: {
                HStack(spacing: 12) {
                    let site = store.site(id: s.siteID)
                    Image(systemName: site?.kind.symbol ?? "tent.fill")
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(site?.kind.color ?? .sunset, in: .rect(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading) {
                        Text(s.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if let site { Text("\(site.priceLabel) · \(site.state)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .onDelete { $0.map { saved[$0] }.forEach(context.delete) }
    }

    @ViewBuilder private var visitList: some View {
        if visits.isEmpty {
            ContentUnavailableView("No visits logged", systemImage: "star",
                                   description: Text("Rate a campsite after you stay. Ratings logged on-site are marked verified."))
                .foregroundStyle(Color.sunshine)
                .listRowBackground(Color.clear)
        }
        ForEach(visits) { v in
            Button { openSite = store.site(id: v.siteID) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(v.siteName).font(.body.weight(.medium)).foregroundStyle(.primary)
                    VisitRow(visit: v)
                }
            }
            .listRowSeparator(.hidden)
        }
        .onDelete { offsets in
            // Take shared copies off the server too, then delete here.
            let doomed = offsets.map { visits[$0] }
            for v in doomed {
                let account = community
                if v.remoteID != nil { Task { await account.deleteRemote(v) ; context.delete(v) } } else { context.delete(v) }
            }
        }
    }
}
