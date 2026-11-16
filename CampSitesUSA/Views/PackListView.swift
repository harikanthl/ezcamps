import SwiftUI

/// The pack list sheet, built to fit a screen: a compact header (what you're doing, people,
/// nights), tabs for Water, Food, Gear and Essentials with how much of each is packed, and one-line
/// rows that open to the detail and source only when tapped.
struct PackListView: View {
    let title: String
    let site: Site?
    let nights: Int
    /// Checklist state is remembered per trip or site.
    let storageKey: String

    enum Tab: String, CaseIterable, Identifiable {
        case water, food, gear, essentials, bears
        var id: String { rawValue }
        var label: String {
            switch self {
            case .water: "Water"
            case .food: "Food"
            case .gear: "Gear"
            case .essentials: "Essentials"
            case .bears: "Bears"
            }
        }
        var icon: String {
            switch self {
            case .water: "droplet"
            case .food: "forkknife"
            case .gear: "boot"
            case .essentials: "compass"
            case .bears: "warning"
            }
        }
        var sectionIDs: [String] {
            switch self {
            case .water: ["water"]
            case .food: ["meals", "snacks", "energy"]
            case .gear: ["gear"]
            case .essentials: ["essentials"]
            case .bears: ["bears"]
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabNS
    @State private var lows: [Int]
    @State private var activities = PackActivity.favorites()
    @State private var people = 2
    @State private var nightsShown: Int
    @State private var bearCountry = false
    @State private var checked: Set<String> = []
    @State private var tab: Tab = .water
    @State private var open: String?

    init(title: String, site: Site?, nights: Int, lows: [Int], storageKey: String) {
        self.title = title
        self.site = site
        self.nights = nights
        self.storageKey = storageKey
        _lows = State(initialValue: lows)
        _nightsShown = State(initialValue: max(1, nights))
    }

    private var input: PackInputs {
        PackInputs(activities: activities, nights: nightsShown, people: people,
                   coldestLow: lows.min(), warmestLow: lows.max(),
                   siteHasWater: site?.amenities.contains("water") ?? false, bearCountry: bearCountry)
    }

    private var sections: [PackSection] { PackPlanner.make(input) }

    private var tabs: [Tab] {
        let ids = Set(sections.map(\.id))
        return Tab.allCases.filter { t in t.sectionIDs.contains(where: ids.contains) }
    }

    private func items(_ t: Tab) -> [PackItem] {
        sections.filter { t.sectionIDs.contains($0.id) }.flatMap(\.items)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    tabBar
                    tabContent
                        .id(tab)
                        .transition(.opacity)
                    Text("Sources: Park Service, CDC, Ready.gov, Academy of Nutrition and Dietetics, NOLS, REI, hunter education. Local rules vary.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Pack for \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
            .onAppear { checked = Set(UserDefaults.standard.stringArray(forKey: "pack.\(storageKey)") ?? []) }
            .onChange(of: checked) { _, v in UserDefaults.standard.set(Array(v), forKey: "pack.\(storageKey)") }
            .onChange(of: tabs) { _, t in if !t.contains(tab), let first = t.first { tab = first } }
            .sensoryFeedback(.selection, trigger: checked.count)
        }
        .presentationDetents([.large])
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PackActivity.allCases) { a in
                        let on = activities.contains(a)
                        Button {
                            activities.formSymmetricDifference([a])
                            PackActivity.saveFavorites(activities)
                        } label: {
                            HStack(spacing: 5) {
                                Icon3D(a.icon3D, size: 16)
                                Text(a.label)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(on ? Color.dusk.opacity(0.18) : Color.secondary.opacity(0.1), in: .capsule)
                            .foregroundStyle(on ? Color.dusk : .primary)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
            HStack(spacing: 8) {
                counter("person", "people", value: $people, range: 1...12)
                counter("night", "nights", value: $nightsShown, range: 1...21)
                if let lo = lows.min() {
                    Label("\(lo)°", systemImage: "thermometer.snowflake")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(lo <= 32 ? Color.sky : .secondary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.1), in: .capsule)
                        .accessibilityLabel("Coldest night \(lo) degrees")
                }
            }
        }
    }

    /// "− 2 people +" in one capsule.
    private func counter(_ one: String, _ many: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
                Image(systemName: "minus").frame(width: 26, height: 26)
            }
            .disabled(value.wrappedValue <= range.lowerBound)
            Text("\(value.wrappedValue) \(value.wrappedValue == 1 ? one : many)")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
            Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
                Image(systemName: "plus").frame(width: 26, height: 26)
            }
            .disabled(value.wrappedValue >= range.upperBound)
        }
        .font(.caption.weight(.bold))
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(Color.secondary.opacity(0.1), in: .capsule)
        .animation(.easeOut(duration: 0.15), value: value.wrappedValue)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { t in
                let list = items(t)
                let done = list.filter { checked.contains($0.id) }.count
                Button {
                    open = nil
                    if reduceMotion { tab = t } else { withAnimation(.spring(duration: 0.3, bounce: 0.1)) { tab = t } }
                } label: {
                    VStack(spacing: 3) {
                        Icon3D(t.icon, size: 22)
                        Text(t.label).font(.caption2.weight(.semibold)).lineLimit(1)
                        Text("\(done)/\(list.count)").font(.caption2.monospacedDigit())
                            .foregroundStyle(done == list.count && !list.isEmpty ? Color.meadow : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "tab", in: tabNS)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .foregroundStyle(tab == t ? .primary : .secondary)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .water: waterCard
        case .essentials: essentialsGrid
        case .food:
            ForEach(sections.filter { Tab.food.sectionIDs.contains($0.id) }) { s in listCard(s) }
        default:
            ForEach(sections.filter { tab.sectionIDs.contains($0.id) }) { s in listCard(s) }
        }
    }

    // MARK: Water

    private var waterCard: some View {
        let liters = PackPlanner.waterLiters(input)
        let section = sections.first { $0.id == "water" }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(liters.rounded()))").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Color.sky)
                    .contentTransition(.numericText())
                Text("L").font(.title3.weight(.bold)).foregroundStyle(Color.sky)
                Text("≈ \(Int((liters / 3.785).rounded())) gal").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            .animation(.easeOut(duration: 0.2), value: liters)
            Text("For \(people) \(people == 1 ? "person" : "people"), \(nightsShown + 1) days. "
                 + ((site?.amenities.contains("water") ?? false) ? "This site lists drinking water." : "No drinking water listed here: bring it, or treat what you find."))
                .font(.subheadline).foregroundStyle(.secondary)
            if let section { rows(section.items) }
        }
        .padding(14)
        .background(Color.sky.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
    }

    // MARK: Essentials

    private var essentialsGrid: some View {
        let list = items(.essentials)
        return VStack(alignment: .leading, spacing: 10) {
            Text("The Park Service's Ten Essentials for anyone leaving camp. Tap to pack; hold for details.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(list) { item in
                    let done = checked.contains(item.id)
                    Button { toggle(item) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? Color.meadow : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                .foregroundStyle(done ? .secondary : .primary)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(done ? Color.meadow.opacity(0.1) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .contextMenu {
                        if let d = item.detail { Text(d) }
                        if let s = item.source, let url = URL.web(s) { Button("Open source", systemImage: "safari") { openURL(url) } }
                    }
                }
            }
        }
    }

    // MARK: Lists

    private func listCard(_ s: PackSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.title).font(.headline)
                Spacer()
                Text("\(s.items.filter { checked.contains($0.id) }.count)/\(s.items.count)")
                    .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            if let summary = s.summary { Text(summary).font(.caption).foregroundStyle(.secondary) }
            rows(s.items)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: .rect(cornerRadius: 20, style: .continuous))
    }

    /// One line per item; tap the text to see why and where it comes from.
    private func rows(_ list: [PackItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { item in
                let done = checked.contains(item.id)
                let expanded = open == item.id
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Button { toggle(item) } label: {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(done ? Color.meadow : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(done ? "Packed" : "Not packed")
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { open = expanded ? nil : item.id }
                        } label: {
                            HStack {
                                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(expanded ? nil : 1)
                                    .strikethrough(done, color: .secondary)
                                    .foregroundStyle(done ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                if item.detail != nil || item.source != nil {
                                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                                        .rotationEffect(.degrees(expanded ? 180 : 0))
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                    if expanded {
                        VStack(alignment: .leading, spacing: 4) {
                            if let d = item.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                            if let s = item.source, let url = URL.web(s) {
                                Button(url.host()?.replacingOccurrences(of: "www.", with: "") ?? "Source") { openURL(url) }
                                    .font(.caption2.weight(.semibold)).foregroundStyle(Color.sky)
                            }
                        }
                        .padding(.leading, 34)
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, 7)
                if item.id != list.last?.id { Divider().padding(.leading, 34) }
            }
        }
    }

    private func toggle(_ item: PackItem) {
        withAnimation(.easeOut(duration: 0.15)) { checked.formSymmetricDifference([item.id]) }
    }

    private func load() async {
        guard let site else { return }
        if lows.isEmpty {
            lows = await ConditionsService.conditions(at: site.coordinate).nights.prefix(max(1, nightsShown)).map(\.low)
        }
        if let w = try? await RatingsAPI.wildlife(near: site.coordinate) {
            bearCountry = w.game.contains { $0.name.localizedCaseInsensitiveContains("bear") }
        }
    }
}
