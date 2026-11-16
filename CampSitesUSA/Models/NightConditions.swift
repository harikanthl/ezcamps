import Foundation
import CoreLocation

/// What the night at a camp looks like: overnight forecast (NWS), active weather alerts (NWS),
/// wildfires nearby (NIFC WFIGS) and smoke / air quality (Open-Meteo, CAMS model).
/// All free, no keys. Each part loads independently, so one slow service doesn't hide the rest.
nonisolated struct NightForecast: Identifiable, Sendable {
    let id: String          // night key, "2026-11-15" = the night starting that evening
    let name: String        // "Tonight", "Monday Night"
    let low: Int            // °F
    let wind: String        // "5 to 10 mph"
    let windDirection: String
    let precipChance: Int?
    let summary: String
}

nonisolated struct WeatherAlert: Identifiable, Sendable {
    let id: String
    let event: String       // "Winter Storm Warning", "Red Flag Warning"
    let headline: String
    let severity: String
}

nonisolated struct NearbyFire: Identifiable, Sendable {
    let id: String
    let name: String
    let acres: Double?
    let contained: Int?
    let miles: Double
}

nonisolated struct NightConditions: Sendable {
    var nights: [NightForecast] = []
    var alerts: [WeatherAlert] = []
    var fires: [NearbyFire] = []
    /// Worst US AQI overnight (6 pm–6 am), keyed like NightForecast.id.
    var aqi: [String: Int] = [:]
    var weatherFailed = false
    var firesFailed = false
    var aqiFailed = false

    func night(_ key: String) -> NightForecast? { nights.first { $0.id == key } }

    static func nightKey(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}

enum ConditionsService {
    static let fireRadiusMiles = 50.0
    private static let userAgent = "ezcamps-ios"
    private static var cache: [String: (Date, NightConditions)] = [:]

    /// Cached for 30 minutes per ~1 km cell.
    static func conditions(at c: CLLocationCoordinate2D) async -> NightConditions {
        let key = String(format: "%.2f,%.2f", c.latitude, c.longitude)
        if let (at, hit) = cache[key], Date.now.timeIntervalSince(at) < 1800 { return hit }
        async let weather = forecast(c)
        async let alerts = activeAlerts(c)
        async let fires = fires(near: c)
        async let air = overnightAQI(c)
        var out = NightConditions()
        if let w = await weather { out.nights = w } else { out.weatherFailed = true }
        out.alerts = await alerts ?? []
        if let f = await fires { out.fires = f } else { out.firesFailed = true }
        if let a = await air { out.aqi = a } else { out.aqiFailed = true }
        if !out.weatherFailed {
            // Bounded: a long session of browsing sites shouldn't grow this forever.
            if cache.count >= 150 {
                cache = cache.filter { Date.now.timeIntervalSince($0.value.0) < 1800 }
                if cache.count >= 150, let oldest = cache.min(by: { $0.value.0 < $1.value.0 })?.key { cache[oldest] = nil }
            }
            cache[key] = (.now, out)
        }
        return out
    }

    // MARK: NWS

    private static func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private struct Points: Decodable {
        struct Props: Decodable { let forecast: String? }
        let properties: Props
    }

    private struct Forecast: Decodable {
        struct Period: Decodable {
            let name: String
            let startTime: String
            let isDaytime: Bool
            let temperature: Int
            let windSpeed: String
            let windDirection: String
            let shortForecast: String
            let probabilityOfPrecipitation: Value?
        }
        struct Value: Decodable { let value: Int? }
        struct Props: Decodable { let periods: [Period] }
        let properties: Props
    }

    private static func forecast(_ c: CLLocationCoordinate2D) async -> [NightForecast]? {
        let p = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        guard let data = await get(URL(string: "https://api.weather.gov/points/\(p)")!),
              let url = (try? JSONDecoder().decode(Points.self, from: data))?.properties.forecast.flatMap(URL.init),
              let fdata = await get(url),
              let f = try? JSONDecoder().decode(Forecast.self, from: fdata) else { return nil }
        return f.properties.periods.filter { !$0.isDaytime }.map {
            NightForecast(id: String($0.startTime.prefix(10)), name: $0.name, low: $0.temperature,
                          wind: $0.windSpeed, windDirection: $0.windDirection,
                          precipChance: $0.probabilityOfPrecipitation?.value, summary: $0.shortForecast)
        }
    }

    private struct Alerts: Decodable {
        struct Feature: Decodable {
            struct Props: Decodable { let id: String; let event: String; let headline: String?; let severity: String }
            let properties: Props
        }
        let features: [Feature]
    }

    private static func activeAlerts(_ c: CLLocationCoordinate2D) async -> [WeatherAlert]? {
        let p = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        guard let data = await get(URL(string: "https://api.weather.gov/alerts/active?point=\(p)")!),
              let a = try? JSONDecoder().decode(Alerts.self, from: data) else { return nil }
        return a.features.map {
            WeatherAlert(id: $0.properties.id, event: $0.properties.event,
                         headline: $0.properties.headline ?? $0.properties.event, severity: $0.properties.severity)
        }
    }

    // MARK: NIFC wildfires

    private struct FireQuery: Decodable {
        struct Feature: Decodable {
            struct Attrs: Decodable {
                let IrwinID: String?
                let IncidentName: String?
                let IncidentSize: Double?
                let PercentContained: Double?
            }
            struct Geo: Decodable { let x: Double; let y: Double }
            let attributes: Attrs
            let geometry: Geo?
        }
        let features: [Feature]
    }

    /// Active wildfires (not prescribed burns) within 50 miles that aren't fully contained.
    private static func fires(near c: CLLocationCoordinate2D) async -> [NearbyFire]? {
        var comps = URLComponents(string: "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Incident_Locations_Current/FeatureServer/0/query")!
        comps.queryItems = [
            .init(name: "where", value: "IncidentTypeCategory='WF'"),
            .init(name: "geometry", value: "\(c.longitude),\(c.latitude)"),
            .init(name: "geometryType", value: "esriGeometryPoint"),
            .init(name: "inSR", value: "4326"),
            .init(name: "spatialRel", value: "esriSpatialRelIntersects"),
            .init(name: "distance", value: "\(Int(fireRadiusMiles))"),
            .init(name: "units", value: "esriSRUnit_StatuteMile"),
            .init(name: "outFields", value: "IrwinID,IncidentName,IncidentSize,PercentContained"),
            .init(name: "returnGeometry", value: "true"),
            .init(name: "outSR", value: "4326"),
            .init(name: "f", value: "json"),
        ]
        guard let data = await get(comps.url!), let q = try? JSONDecoder().decode(FireQuery.self, from: data) else { return nil }
        return q.features.compactMap { f -> NearbyFire? in
            guard let g = f.geometry, (f.attributes.PercentContained ?? 0) < 100 else { return nil }
            return NearbyFire(id: f.attributes.IrwinID ?? UUID().uuidString,
                              name: (f.attributes.IncidentName ?? "Unnamed").capitalized + " Fire",
                              acres: f.attributes.IncidentSize,
                              contained: f.attributes.PercentContained.map { Int($0) },
                              miles: TripPlanner.miles(c, .init(latitude: g.y, longitude: g.x)))
        }
        .sorted { $0.miles < $1.miles }
    }

    // MARK: Open-Meteo air quality

    private struct Air: Decodable {
        struct Hourly: Decodable { let time: [String]; let us_aqi: [Int?] }
        let hourly: Hourly
    }

    /// Worst AQI from 6 pm to 6 am for each night in the 5-day model forecast (camp's local time).
    private static func overnightAQI(_ c: CLLocationCoordinate2D) async -> [String: Int]? {
        let url = URL(string: String(format: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%.4f&longitude=%.4f&hourly=us_aqi&forecast_days=5&timezone=auto", c.latitude, c.longitude))!
        guard let data = await get(url), let a = try? JSONDecoder().decode(Air.self, from: data) else { return nil }
        var out: [String: Int] = [:]
        let days = a.hourly.time.map { String($0.prefix(10)) }
        let orderedDays = Array(NSOrderedSet(array: days)) as? [String] ?? []
        for (i, t) in a.hourly.time.enumerated() {
            guard let v = a.hourly.us_aqi[i], let hour = Int(t.dropFirst(11).prefix(2)) else { continue }
            let day = String(t.prefix(10))
            let key: String
            if hour >= 18 {
                key = day
            } else if hour < 6, let idx = orderedDays.firstIndex(of: day), idx > 0 {
                key = orderedDays[idx - 1]  // early-morning hours belong to the previous evening's night
            } else { continue }
            out[key] = max(out[key] ?? 0, v)
        }
        return out
    }
}

// MARK: - Display helpers

nonisolated enum AQILevel {
    static func label(_ aqi: Int) -> String {
        switch aqi {
        case ..<51: "Good"
        case ..<101: "Moderate"
        case ..<151: "Unhealthy for sensitive groups"
        case ..<201: "Unhealthy"
        case ..<301: "Very unhealthy"
        default: "Hazardous"
        }
    }

    static func short(_ aqi: Int) -> String {
        switch aqi {
        case ..<51: "Good"
        case ..<101: "Moderate"
        case ..<151: "Sensitive"
        case ..<201: "Unhealthy"
        default: "Very unhealthy"
        }
    }
}

nonisolated enum SkySymbol {
    static func night(_ summary: String) -> String {
        let s = summary.lowercased()
        if s.contains("thunder") { return "cloud.bolt.rain.fill" }
        if s.contains("snow") || s.contains("flurr") { return "cloud.snow.fill" }
        if s.contains("rain") || s.contains("shower") || s.contains("drizzle") { return "cloud.moon.rain.fill" }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") { return "cloud.fog.fill" }
        if s.contains("wind") || s.contains("breezy") { return "wind" }
        if s.contains("mostly cloudy") || s.contains("cloudy") && !s.contains("partly") { return "cloud.fill" }
        if s.contains("partly") { return "cloud.moon.fill" }
        return "moon.stars.fill"
    }
}
