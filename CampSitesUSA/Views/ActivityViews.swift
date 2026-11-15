import SwiftUI
import MapKit

extension Activity.Difficulty {
    var color: Color {
        switch self {
        case .easy: .meadow
        case .moderate: .sky
        case .hard: .canyon
        case .strenuous: .berry
        }
    }
}

struct DifficultyBadge: View {
    let difficulty: Activity.Difficulty?

    var body: some View {
        if let difficulty {
            Badge(text: difficulty.label, color: difficulty.color)
        } else {
            Text("Not rated")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.quaternary, in: .capsule)
        }
    }
}

// MARK: - Section on the site card

/// "Things to do nearby", ranked easiest first, with a difficulty filter.
struct NearbyActivitiesSection: View {
    let site: Site
    @Environment(SiteStore.self) private var store
    @State private var level: Activity.Difficulty?
    @State private var all: [NearbyActivity] = []

    private static let radius = 25.0
    private var shown: [NearbyActivity] { level.map { l in all.filter { $0.activity.difficulty == l } } ?? all }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Things to do nearby").font(.headline)
                Text("Within \(Int(Self.radius)) mi · easiest first").font(.caption).foregroundStyle(.secondary)
            }

            if all.isEmpty {
                Text(store.activities.isEmpty ? "Loading activities…" : "No trails or activities in our data within \(Int(Self.radius)) miles yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "All \(all.count)", tint: .sunset, isOn: level == nil) { level = nil }
                        ForEach(Activity.Difficulty.allCases, id: \.self) { d in
                            let n = all.count { $0.activity.difficulty == d }
                            if n > 0 {
                                Chip(title: "\(d.label) \(n)", tint: d.color, isOn: level == d) {
                                    level = level == d ? nil : d
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(shown.prefix(5)) { item in
                        NavigationLink { ActivityDetailView(item: item) } label: { ActivityRow(item: item) }
                            .buttonStyle(.pressable)
                        if item.id != shown.prefix(5).last?.id { Divider().padding(.leading, 52) }
                    }
                }

                if shown.count > 5 {
                    NavigationLink {
                        ActivityListView(title: "Near \(site.name)", items: shown)
                    } label: {
                        Text("See all \(shown.count)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(Color.sunset)
                            .background(Color.sunset.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .task(id: store.activities.count) {
            all = store.activities(near: site.coordinate, radius: Self.radius)
        }
    }
}

struct ActivityRow: View {
    let item: NearbyActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.activity.type.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(item.activity.difficulty?.color ?? .secondary, in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.activity.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    .foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            DifficultyBadge(difficulty: item.activity.difficulty)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts = [item.activity.type.label]
        if let m = item.activity.miles { parts.append("\(m.formatted(.number.precision(.fractionLength(1)))) mi") }
        else if let d = item.activity.duration { parts.append(d.lowercased()) }
        parts.append("\(item.distance.formatted(.number.precision(.fractionLength(item.distance < 10 ? 1 : 0)))) mi away")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Full list

struct ActivityListView: View {
    let title: String
    let items: [NearbyActivity]
    @State private var kind: Activity.Kind?

    private var kinds: [Activity.Kind] { Activity.Kind.allCases.filter { k in items.contains { $0.activity.type == k } } }
    private var shown: [NearbyActivity] { kind.map { k in items.filter { $0.activity.type == k } } ?? items }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "All", tint: .sunset, isOn: kind == nil) { kind = nil }
                        ForEach(kinds, id: \.self) { k in
                            Chip(title: k.label, symbol: k.symbol, tint: .dusk, isOn: kind == k) {
                                kind = kind == k ? nil : k
                            }
                        }
                    }
                }
                .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            Section {
                ForEach(shown) { item in
                    NavigationLink { ActivityDetailView(item: item) } label: { ActivityRow(item: item) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Detail

struct ActivityDetailView: View {
    let item: NearbyActivity
    private var a: Activity { item.activity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Badge(text: a.type.label, symbol: a.type.symbol, color: .dusk)
                        DifficultyBadge(difficulty: a.difficulty)
                    }
                    Text(a.name).font(.title2.weight(.bold))
                    if let place = a.place { Text(place).font(.subheadline).foregroundStyle(.secondary) }
                }

                HStack(spacing: 10) {
                    ActionTile(title: "Directions", symbol: "arrow.triangle.turn.up.right.diamond.fill", color: .sunset, filled: true) {
                        let item = MKMapItem(location: CLLocation(latitude: a.lat, longitude: a.lon), address: nil)
                        item.name = a.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                    }
                    if let s = a.url, let url = URL(string: s) {
                        Link(destination: url) {
                            VStack(spacing: 6) {
                                Image(systemName: "safari.fill").font(.title3.weight(.semibold))
                                Text("Details").font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(Color.sky)
                            .background(Color.sky.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    if let m = a.miles { LabeledContent("Length", value: "\(m.formatted(.number.precision(.fractionLength(1)))) mi") }
                    if let d = a.duration { LabeledContent("Duration", value: d) }
                    LabeledContent("From camp", value: "\(item.distance.formatted(.number.precision(.fractionLength(1)))) mi")
                    if let uses = a.uses, !uses.isEmpty {
                        LabeledContent("Allowed", value: uses.split(separator: ";").map { $0.capitalized }.joined(separator: ", "))
                    }
                }
                .font(.subheadline)

                difficultyExplainer

                if let d = a.description { Text(d).font(.body) }

                Text(a.source == "nps" ? "From the National Park Service." : "From the USDA Forest Service (CC BY 4.0).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(alignment: .top) {
            LinearGradient(colors: [(a.difficulty?.color ?? .secondary).opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 200).ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Always say where the grade came from, so people can judge it.
    private var difficultyExplainer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(a.difficulty.map { "Why \($0.label.lowercased())?" } ?? "Not rated", systemImage: "gauge.with.dots.needle.50percent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(a.difficulty?.color ?? .secondary)
            Text(a.basis.map { "Based on \($0)." } ?? "We don't have trail class, grade or a park description for this yet.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((a.difficulty?.color ?? .secondary).opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
    }
}
