import SwiftUI
import MapKit

/// "Safety" on the site card. Four parts, each with its source:
/// 1. What campers reported (safety tags on shared ratings, last 4 months).
/// 2. Current National Park Service alerts for the park the site is in or near.
/// 3. How far help is: nearest hospital and police or ranger station.
/// 4. County context from FBI crime data, for the whole sheriff's area, never this exact spot.
struct SafetySection: View {
    let site: Site
    /// Shared ratings for this site (loaded once by the site card).
    let community: SiteCommunity?

    @Environment(SiteStore.self) private var store
    @State private var alerts: [ParkAlert]?
    @State private var alertsFailed = false
    @State private var hospital: ServicePlace??
    @State private var police: ServicePlace??
    @State private var expandedAlert: String?

    private var county: CountyInfo? { store.safety?.county(for: site.id) }
    private var parks: [String] { store.safety?.parks(for: site.id) ?? [] }

    private var safetyTags: [RecentTag] {
        (community?.recentTags ?? []).filter { SafetyTag.isSafety($0.tag) }
            .sorted { (SafetyTag.concerning.contains($0.tag) ? 0 : 1, -$0.count) < (SafetyTag.concerning.contains($1.tag) ? 0 : 1, -$1.count) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Safety", icon: "shield")
            reports
            if !parks.isEmpty { parkAlerts }
            help
            if let county { countyContext(county) }
            Text("A heads-up, not a guarantee. Trust your instincts, lock up valuables, and tell someone where you're camping.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: site.id) { await load() }
    }

    // MARK: Camper reports

    @ViewBuilder private var reports: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From campers").font(.subheadline.weight(.semibold))
            if community == nil {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            } else if safetyTags.isEmpty {
                Text("No safety reports in the last 4 months. Rate your stay to add one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(safetyTags, id: \.tag) { t in
                        let bad = SafetyTag.concerning.contains(t.tag)
                        HStack(spacing: 4) {
                            Image(systemName: bad ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                            Text(t.tag).fontWeight(.semibold)
                            Text(detail(t)).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(bad ? Color.berry : Color.meadow)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background((bad ? Color.berry : Color.meadow).opacity(0.12), in: .capsule)
                    }
                }
            }
        }
    }

    private func detail(_ t: RecentTag) -> String {
        var parts = ["\(t.count)×"]
        if let v = t.verified, v > 0 { parts.append("\(v) verified") }
        if let d = RatingsAPI.day(t.latest) { parts.append(CommunityRatingsSection.age(d)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Park alerts

    @ViewBuilder private var parkAlerts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Park alerts").font(.subheadline.weight(.semibold))
            if let alerts {
                if alerts.isEmpty {
                    Label("No current alerts from the Park Service", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Color.meadow)
                } else {
                    ForEach(alerts.prefix(4)) { a in alertRow(a) }
                }
            } else if alertsFailed {
                Text("Park alerts aren't available right now. Check the park's website before you go.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Checking park alerts…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func alertRow(_ a: ParkAlert) -> some View {
        let color: Color = a.rank == 0 ? .berry : a.rank == 1 ? .canyon : a.rank == 2 ? .sunshine : .sky
        let open = expandedAlert == a.id
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { expandedAlert = open ? nil : a.id }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: a.rank <= 1 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.title).font(.caption.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text("\(a.category) · \(a.park.uppercased())").font(.caption2).foregroundStyle(.secondary)
                    if open {
                        Text(a.description).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        if let url = URL.web(a.url) {
                            Link("More from the Park Service", destination: url).font(.caption.weight(.semibold))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Nearest help

    private var help: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nearest help").font(.subheadline.weight(.semibold))
            helpRow(icon: "hospital", label: "Hospital", result: hospital)
            helpRow(icon: "police", label: "Police or ranger station", result: police)
        }
    }

    @ViewBuilder private func helpRow(icon: String, label: String, result: ServicePlace??) -> some View {
        HStack(spacing: 8) {
            Icon3D(icon, size: 22)
            switch result {
            case .none:
                Text("\(label): searching…").font(.caption).foregroundStyle(.secondary)
            case .some(.none):
                Text("\(label): none found within 80 mi").font(.caption.weight(.semibold)).foregroundStyle(Color.canyon)
            case .some(.some(let p)):
                Button { p.item.openInMaps() } label: {
                    Text("\(p.name) · \(p.miles.formatted(.number.precision(.fractionLength(p.miles < 10 ? 1 : 0)))) mi")
                        .lineLimit(1)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens in Maps")
            }
        }
    }

    // MARK: County context

    @ViewBuilder private func countyContext(_ c: CountyInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Area context: \(c.name), \(c.state)").font(.subheadline.weight(.semibold))
            if let crime = c.crime {
                let year = store.safety?.crimeYear.map(String.init) ?? "the latest year"
                if crime.isSmall {
                    countRow("Violent crime", count: crime.violentCount, year: year)
                    countRow("Property crime", count: crime.propertyCount, year: year)
                } else {
                    crimeRow("Violent crime", rate: crime.violent, state: crime.state_violent, us: crime.us_violent)
                    crimeRow("Property crime", rate: crime.property, state: crime.state_property, us: crime.us_property)
                }
                Text("FBI Crime Data Explorer, \(crime.agency), \(year). Covers the sheriff's whole area, not this campsite."
                     + (crime.isSmall ? " Fewer than 5,000 people live here, so we show counts, not rates."
                        : " Rates are per resident, so places with many visitors can look higher than they feel."))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No FBI crime data for this county's sheriff's office.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func countRow(_ title: String, count: Double?, year: String) -> some View {
        if let count {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(count)) reported in \(year)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func crimeRow(_ title: String, rate: Double?, state: Double?, us: Double?) -> some View {
        if let rate {
            let cmp = CrimeComparison(rate: rate, us: us)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if let cmp {
                        Text(cmp.label).font(.caption.weight(.semibold))
                            .foregroundStyle(cmp == .higher || cmp == .muchHigher ? Color.canyon : Color.meadow)
                    }
                    Text("\(Int(rate.rounded())) per 100k" + (state.map { " · state \(Int($0.rounded()))" } ?? "")
                         + (us.map { " · US \(Int($0.rounded()))" } ?? ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Loading

    private func load() async {
        async let a: [ParkAlert]? = parks.isEmpty ? [] : (try? await RatingsAPI.alerts(parks: parks))
        async let h = ServiceFinder.nearest(.hospital, to: site.coordinate)
        async let p = ServiceFinder.nearest(.police, to: site.coordinate)
        let (alertList, hosp, pol) = await (a, h, p)
        guard !Task.isCancelled else { return }
        if let alertList { alerts = alertList.sorted { $0.rank < $1.rank } } else { alertsFailed = true }
        hospital = .some(hosp)
        police = .some(pol)
    }
}
