import SwiftUI
import CoreLocation
import os

extension Color {
    static func aqi(_ v: Int) -> Color {
        switch v {
        case ..<51: .meadow
        case ..<101: Color(hex: 0xE0A800)   // darker sunshine so text stays readable
        case ..<151: .canyon
        case ..<201: .berry
        default: .dusk
        }
    }

    static func lowTemp(_ f: Int) -> Color {
        f <= 32 ? .sky : f <= 45 ? .dusk : .sunset
    }
}

/// "Night conditions" on the site card: the next nights' lows, wind and rain chance, smoke,
/// active weather alerts and wildfires within 50 miles.
struct NightConditionsSection: View {
    let coordinate: CLLocationCoordinate2D
    /// When set, gear tips for the next few nights at this site appear below.
    var site: Site?
    @State private var data: NightConditions?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Night conditions", icon: "moon")

            if let data {
                ForEach(data.alerts) { alert in
                    banner(symbol: "exclamationmark.triangle.fill", color: .berry, title: alert.event, detail: alert.headline)
                }

                if data.nights.isEmpty {
                    Text(data.weatherFailed ? "Forecast unavailable right now." : "No forecast for this spot.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(data.nights.prefix(7)) { n in NightCard(night: n, aqi: data.aqi[n.id]) }
                        }
                    }
                    .scrollClipDisabled()
                }

                fires(data)

                Text("Forecast and alerts: National Weather Service. Fires: NIFC. Smoke: Open-Meteo air-quality model.")
                    .font(.caption2).foregroundStyle(.secondary)

                if let site {
                    let next = Array(data.nights.prefix(3))
                    GearTipsSection(tips: GearAdvisor.tips(nights: next, aqi: next.compactMap { data.aqi[$0.id] },
                                                           sites: [(site, 1)]))
                        .padding(.top, 6)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking tonight's weather, smoke and fires…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            data = await ConditionsService.conditions(at: coordinate)
            #if DEBUG
            if let site, let d = data {
                let next = Array(d.nights.prefix(3))
                let tips = GearAdvisor.tips(nights: next, aqi: next.compactMap { d.aqi[$0.id] }, sites: [(site, 1)])
                Logger(subsystem: "ezcamps", category: "Gear").notice("gear \(site.name, privacy: .public): \(tips.map { "\($0.title) — \($0.why)" }.joined(separator: " | "), privacy: .public)")
            }
            #endif
        }
    }

    @ViewBuilder private func fires(_ data: NightConditions) -> some View {
        if data.firesFailed {
            Text("Couldn't check for wildfires right now.").font(.subheadline).foregroundStyle(.secondary)
        } else if data.fires.isEmpty {
            Label("No active wildfires within \(Int(ConditionsService.fireRadiusMiles)) mi", systemImage: "checkmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.meadow)
        } else {
            ForEach(data.fires.prefix(3)) { f in
                banner(symbol: "flame.fill", color: f.miles < 15 ? .berry : .canyon,
                       title: "\(f.name) · \(Int(f.miles.rounded())) mi away",
                       detail: fireDetail(f))
            }
        }
    }

    private func fireDetail(_ f: NearbyFire) -> String {
        var parts: [String] = []
        if let a = f.acres { parts.append("\(Int(a).formatted()) acres") }
        if let c = f.contained { parts.append("\(c)% contained") }
        parts.append("Check closures before you go")
        return parts.joined(separator: " · ")
    }

    private func banner(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.body.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

/// One night. Every card is the same size no matter how long the forecast text is: each row has
/// a fixed slot (one or two lines, truncated), and the card size scales with Dynamic Type.
private struct NightCard: View {
    let night: NightForecast
    let aqi: Int?
    @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 132
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 178

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(night.name == "Tonight" ? "Tonight" : night.name.replacingOccurrences(of: " Night", with: ""))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: SkySymbol.night(night.summary)).symbolRenderingMode(.multicolor)
                Text("\(night.low)°").font(.title2.weight(.bold)).foregroundStyle(Color.lowTemp(night.low))
            }
            .lineLimit(1)
            // Two-line slot whether the forecast is "Clear" or "Rain And Snow Showers Likely".
            Text(night.summary)
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
            Label(windText, systemImage: "wind")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Label(precipText, systemImage: "drop.fill")
                .font(.caption2)
                .foregroundStyle(Color.sky)
                .lineLimit(1)
                .opacity((night.precipChance ?? 0) > 0 ? 1 : 0)  // keep the row so cards line up
            Spacer(minLength: 0)
            if let aqi {
                Text("AQI \(aqi) · \(AQILevel.short(aqi))")
                    .font(.caption2.weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.aqi(aqi), in: .capsule)
            }
        }
        .padding(10)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Color.lowTemp(night.low).opacity(0.1), in: .rect(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var windText: String {
        night.wind == "0 mph" ? "Calm" : "\(night.windDirection) \(night.wind)"
    }

    private var precipText: String { "\(night.precipChance ?? 0)% chance" }

    /// Full text for VoiceOver, since the card truncates.
    private var accessibilityText: String {
        var parts = ["\(night.name): low \(night.low) degrees", night.summary, "wind \(windText)"]
        if let p = night.precipChance, p > 0 { parts.append("\(p) percent chance of precipitation") }
        if let aqi { parts.append("air quality \(aqi), \(AQILevel.label(aqi))") }
        return parts.joined(separator: ", ")
    }
}

/// One-line night summary for a trip day ("28° · wind 10 mph · AQI 35 · no fires nearby").
struct TripNightLine: View {
    let conditions: NightConditions?
    let nightKey: String?

    var body: some View {
        if let c = conditions {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let key = nightKey, let n = c.night(key) {
                        pill("\(n.low)° \(shortSky(n.summary))", symbol: SkySymbol.night(n.summary), color: Color.lowTemp(n.low))
                        if n.wind != "0 mph" { pill(n.wind, symbol: "wind", color: .secondary) }
                    } else if nightKey != nil {
                        pill("Forecast shows up 7 days out", symbol: "calendar", color: .secondary)
                    }
                    if let key = nightKey, let aqi = c.aqi[key], aqi > 50 {
                        pill("AQI \(aqi)", symbol: "aqi.medium", color: .aqi(aqi))
                    }
                    if let f = c.fires.first {
                        pill("Fire \(Int(f.miles.rounded())) mi", symbol: "flame.fill", color: f.miles < 15 ? .berry : .canyon)
                    }
                    if let a = c.alerts.first {
                        pill(a.event, symbol: "exclamationmark.triangle.fill", color: .berry)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func shortSky(_ s: String) -> String {
        let first = s.components(separatedBy: " then ").first ?? s
        return first.count > 18 ? "" : first.lowercased()
    }

    private func pill(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: .capsule)
    }
}
