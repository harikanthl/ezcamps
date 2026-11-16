import Foundation
import SwiftData
import MapKit
import OperatorLLM

/// What "Ask ezcamp" can look up. Every tool reads ezcamp's own data or the same public services
/// the site card uses, so an answer can always say where it came from, and the model can never
/// invent a campground: it only ever sees site ids the search returned.
///
/// Parameters stay flat (strings, numbers, booleans) so the same catalog also works on Apple's
/// on-device model, whose tool bridge can't express arrays or nested objects.
@MainActor
final class ChatTools {
    private let store: SiteStore
    private let location: LocationProvider
    private let context: ModelContext
    /// Where the map is looking, for "near here" / "on the map".
    var mapCenter: () -> CLLocationCoordinate2D?
    /// Sites the conversation is about, for the map to highlight.
    private(set) var mentioned: [String] = []
    /// A trip the chat just created, for an "Open trip" button.
    private(set) var createdTrip: Trip?

    init(store: SiteStore, location: LocationProvider, context: ModelContext, mapCenter: @escaping () -> CLLocationCoordinate2D?) {
        self.store = store
        self.location = location
        self.context = context
        self.mapCenter = mapCenter
    }

    func resetTurn() {
        mentioned = []
        createdTrip = nil
    }

    // MARK: Catalog

    static let specs: [LLMToolSpec] = [
        LLMToolSpec(name: "search_campsites", description: "Find campsites near a place. Returns ids, names, price, kind, distance and amenities. Always use this before naming any campsite.",
                    parametersJSON: """
                    {"type":"object","properties":{
                      "near":{"type":"string","description":"A city, park or address; 'map' for the area on screen; 'me' for the person's location."},
                      "radius_miles":{"type":"number","description":"Search radius, default 25."},
                      "free_only":{"type":"boolean","description":"Only free or likely-free sites."},
                      "kind":{"type":"string","enum":["any","campground","dispersed","rv_park"]},
                      "amenities":{"type":"string","description":"Comma-separated: water, toilets, showers, dump, electric."}
                    },"required":["near"]}
                    """),
        LLMToolSpec(name: "campsite_details", description: "Fee, amenities, stay limit, max vehicle length, cell notes, source, and ratings from other campers for one campsite.",
                    parametersJSON: #"{"type":"object","properties":{"site_id":{"type":"string"}},"required":["site_id"]}"#),
        LLMToolSpec(name: "can_i_camp_here", description: "Who manages the land at a campsite or at the map center, and the usual camping rules there (BLM land manager map).",
                    parametersJSON: #"{"type":"object","properties":{"site_id":{"type":"string","description":"A site id, or omit to use the map center."}}}"#),
        LLMToolSpec(name: "night_conditions", description: "Next nights' lows, wind, rain chance, weather alerts, wildfires within 50 miles and overnight smoke at a campsite.",
                    parametersJSON: #"{"type":"object","properties":{"site_id":{"type":"string"}},"required":["site_id"]}"#),
        LLMToolSpec(name: "safety", description: "Safety heads-up for a campsite: camper safety reports, nearest hospital and police or ranger station, and county crime context (FBI).",
                    parametersJSON: #"{"type":"object","properties":{"site_id":{"type":"string"}},"required":["site_id"]}"#),
        LLMToolSpec(name: "fishing_hunting", description: "Fish and game recorded near a campsite (iNaturalist), live river flow (USGS), and the state's fishing and hunting license rules.",
                    parametersJSON: #"{"type":"object","properties":{"site_id":{"type":"string"}},"required":["site_id"]}"#),
        LLMToolSpec(name: "things_to_do", description: "Hikes, rides, paddles and other activities within 25 miles of a campsite, easiest first.",
                    parametersJSON: #"{"type":"object","properties":{"site_id":{"type":"string"},"difficulty":{"type":"string","enum":["any","easy","moderate","hard","strenuous"]}},"required":["site_id"]}"#),
        LLMToolSpec(name: "pack_list", description: "What to bring for a stay: water amounts, meals, snacks, gear for the activities, and bear storage if bears are around. Each line has a source.",
                    parametersJSON: """
                    {"type":"object","properties":{
                      "site_id":{"type":"string"},
                      "activities":{"type":"string","description":"Comma-separated: camping, dayHiking, backpacking, mountainBiking, trailRunning, fishing, hunting."},
                      "nights":{"type":"integer"},
                      "people":{"type":"integer"}
                    },"required":["site_id"]}
                    """),
        LLMToolSpec(name: "plan_trip", description: "Plan and save a road trip with a camp at the end of each day's drive. Use only when the person asks to plan or save a trip.",
                    parametersJSON: """
                    {"type":"object","properties":{
                      "from":{"type":"string","description":"Start place, or 'me'."},
                      "to":{"type":"string"},
                      "via":{"type":"string","description":"Comma-separated places to stop at, in order."},
                      "nights":{"type":"integer"},
                      "daily_miles":{"type":"integer","description":"Most miles to drive in a day, default 250."},
                      "free_only":{"type":"boolean"}
                    },"required":["to"]}
                    """),
    ]

    /// Reads that can run side by side when the model asks for several at once.
    static func parallelSafe(_ call: LLMToolCall) -> Bool { call.name != "plan_trip" }

    // MARK: Dispatch

    /// Always answers with a JSON string; failures are answers too, so the model can say so.
    func run(_ call: LLMToolCall) async -> String {
        let a = call.arguments
        do {
            let value: Any
            switch call.name {
            case "search_campsites": value = try await search(a)
            case "campsite_details": value = try await details(site(a))
            case "can_i_camp_here": value = try await landCheck(a)
            case "night_conditions": value = await conditions(try site(a))
            case "safety": value = await safety(try site(a))
            case "fishing_hunting": value = await fishing(try site(a))
            case "things_to_do": value = try thingsToDo(a)
            case "plan_trip": value = try await planTrip(a)
            case "pack_list": value = try await packList(a)
            default: throw ToolError("Unknown tool \(call.name).")
            }
            return Self.json(value)
        } catch {
            return Self.json(["error": (error as? ToolError)?.message ?? error.localizedDescription])
        }
    }

    struct ToolError: Error { let message: String; init(_ m: String) { message = m } }

    private func site(_ a: [String: Any]) throws -> Site {
        guard let id = a["site_id"] as? String, let s = store.site(id: id) else {
            throw ToolError("No campsite with that id. Use search_campsites first and pass one of its ids.")
        }
        if !mentioned.contains(s.id) { mentioned.append(s.id) }
        return s
    }

    private func resolvePlace(_ raw: String) async throws -> (name: String, coordinate: CLLocationCoordinate2D) {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if q == "me" || q == "my location" || q == "here" {
            guard let c = location.location?.coordinate else { throw ToolError("Location is off. Ask the person where they are.") }
            return ("your location", c)
        }
        if q == "map" || q == "on screen" {
            guard let c = mapCenter() else { throw ToolError("The map hasn't loaded yet.") }
            return ("the area on the map", c)
        }
        guard let p = await TripPlanner.place(named: raw, near: location.location?.coordinate ?? mapCenter()) else {
            throw ToolError("Couldn't find “\(raw)”. Try a city or park name.")
        }
        return (p.name, p.coordinate)
    }

    // MARK: Tools

    private func search(_ a: [String: Any]) async throws -> [String: Any] {
        let place = try await resolvePlace(a["near"] as? String ?? "map")
        let radius = min(max((a["radius_miles"] as? Double) ?? Double(a["radius_miles"] as? Int ?? 25), 2), 100)
        var filter = SiteFilter()
        filter.freeOnly = a["free_only"] as? Bool ?? false
        switch a["kind"] as? String {
        case "campground": filter.kinds = [.campground]
        case "dispersed": filter.kinds = [.dispersed]
        case "rv_park": filter.kinds = [.rvPark]
        default: filter.kinds = Set(Site.Kind.allCases)
        }
        if let list = a["amenities"] as? String {
            filter.amenities = Set(list.split(separator: ",").compactMap { Amenity(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) })
        }
        let found = store.sites(near: place.coordinate, radius: radius)
            .filter { $0.isNamed && !$0.isBare && filter.matches($0) }
            .map { ($0, TripPlanner.miles($0.coordinate, place.coordinate)) }
            .sorted { TripPlanner.score($0.0, target: place.coordinate, preferFree: filter.freeOnly) > TripPlanner.score($1.0, target: place.coordinate, preferFree: filter.freeOnly) }
            .prefix(8)
        for (s, _) in found where !mentioned.contains(s.id) { mentioned.append(s.id) }
        return [
            "near": place.name,
            "results": found.map { s, d in
                ["site_id": s.id, "name": s.name, "price": s.priceLabel, "kind": s.kind.label,
                 "miles_away": Self.miles(d), "state": s.state, "amenities": s.amenities] as [String: Any]
            },
            "source": "ezcamp campsites (NPS, Recreation.gov, Forest Service, BLM, OpenStreetMap)",
        ]
    }

    private func details(_ s: Site) async throws -> [String: Any] {
        var out: [String: Any] = [
            "site_id": s.id, "name": s.name, "kind": s.kind.label, "price": s.priceLabel, "reservable": s.reservable,
            "amenities": s.amenities, "source": s.source.label, "state": s.state,
            "latitude": s.lat, "longitude": s.lon,
        ]
        if let v = s.stayLimit { out["stay_limit"] = v }
        if let v = s.maxVehicleLength { out["max_vehicle_ft"] = Int(v) }
        if let v = s.cell { out["cell_reception_nps"] = v }
        if let v = s.openingHours { out["season"] = v }
        if let v = s.description { out["about"] = String(v.prefix(400)) }
        if let c = try? await RatingsAPI.site(s.id, token: nil) {
            out["campers"] = ["score": c.summary.score as Any, "count": c.summary.count, "verified": c.summary.verifiedCount,
                              "recent_tags": c.recentTags.prefix(6).map { "\($0.tag) (\($0.count)×, latest \($0.latest))" }]
        }
        return out
    }

    private func landCheck(_ a: [String: Any]) async throws -> [String: Any] {
        let c: CLLocationCoordinate2D
        if a["site_id"] != nil { c = try site(a).coordinate }
        else if let m = mapCenter() { c = m }
        else { throw ToolError("Pass a site id.") }
        let r = try await LandCheck.lookup(c)
        return ["manager": r.agencyName, "unit": r.unitName as Any, "verdict": r.verdict.label, "summary": r.summary,
                "rules": r.rules, "source": "BLM Surface Management Agency map. Local closures and fire restrictions always win."]
    }

    private func conditions(_ s: Site) async -> [String: Any] {
        let c = await ConditionsService.conditions(at: s.coordinate)
        return [
            "nights": c.nights.prefix(4).map { ["night": $0.name, "low_f": $0.low, "wind": "\($0.windDirection) \($0.wind)",
                                                 "rain_chance": $0.precipChance as Any, "forecast": $0.summary,
                                                 "aqi": c.aqi[$0.id] as Any] as [String: Any] },
            "alerts": c.alerts.map(\.headline),
            "wildfires_within_50mi": c.fires.prefix(3).map { "\($0.name), \(Int($0.miles)) mi, \($0.contained.map { "\($0)% contained" } ?? "")" },
            "source": "National Weather Service, NIFC, Open-Meteo",
        ]
    }

    private func safety(_ s: Site) async -> [String: Any] {
        async let h = ServiceFinder.nearest(.hospital, to: s.coordinate)
        async let p = ServiceFinder.nearest(.police, to: s.coordinate)
        async let c = try? RatingsAPI.site(s.id, token: nil)
        let (hosp, pol, comm) = await (h, p, c)
        var out: [String: Any] = [
            "nearest_hospital": hosp.map { "\($0.name), \(Int($0.miles.rounded())) mi" } ?? "none within 150 mi",
            "nearest_police_or_ranger": pol.map { "\($0.name), \(Int($0.miles.rounded())) mi" } ?? "none within 80 mi",
            "camper_safety_reports": (comm?.recentTags ?? []).filter { SafetyTag.isSafety($0.tag) }.map { "\($0.tag) (\($0.count)×, latest \($0.latest))" },
        ]
        if let county = store.safety?.county(for: s.id) {
            var cty: [String: Any] = ["county": "\(county.name), \(county.state)"]
            if let cr = county.crime {
                cty["violent_per_100k"] = cr.violent as Any; cty["us_violent_per_100k"] = cr.us_violent as Any
                cty["property_per_100k"] = cr.property as Any; cty["us_property_per_100k"] = cr.us_property as Any
                cty["note"] = "FBI \(store.safety?.crimeYear.map(String.init) ?? ""), \(cr.agency): the sheriff's whole area, not this campsite."
            }
            out["county_context"] = cty
        }
        return out
    }

    private func fishing(_ s: Site) async -> [String: Any] {
        async let w = try? RatingsAPI.wildlife(near: s.coordinate)
        async let g = StreamFlow.gauges(near: s.coordinate)
        let (wild, gauges) = await (w, g)
        var out: [String: Any] = [
            "game_fish": (wild?.gameFish ?? []).prefix(10).map { "\($0.name)\($0.protected ? " (at-risk)" : "") \($0.observations) sightings" },
            "game_animals": (wild?.game ?? []).prefix(10).map { "\($0.name)\($0.protected ? " (at-risk)" : "") \($0.observations) sightings" },
            "river_flow": (gauges ?? []).prefix(3).map { "\($0.name): \(Int($0.cfs)) cfs, \(Int($0.miles)) mi" },
            "source": "iNaturalist research-grade sightings within 25 km; USGS live flow",
        ]
        if s.source == .nps { out["hunting_note"] = "Hunting isn't allowed in most national parks." }
        if let r = LicenseBook.state(s.state) {
            out["fishing_license"] = [r.fishing?.licenseRequiredFromAge.map { "Needed from age \($0)" } ?? "Required", r.fishing?.licenseUrl ?? ""]
            out["hunting_rules"] = [r.hunting?.hunterEducation ?? "", r.hunting?.blazeOrange ?? "", r.hunting?.licenseUrl ?? ""]
            out["agency"] = r.agency ?? ""
        }
        return out
    }

    private func thingsToDo(_ a: [String: Any]) throws -> [String: Any] {
        let s = try site(a)
        let want = (a["difficulty"] as? String).flatMap { d in Activity.Difficulty.allCases.first { $0.label.lowercased() == d } }
        let list = store.activities(near: s.coordinate).filter { want == nil || $0.activity.difficulty == want }.prefix(10)
        return ["activities": list.map { n in
            ["name": n.activity.name, "type": n.activity.type.label, "difficulty": n.activity.difficulty?.label ?? "unrated",
             "miles_away": Self.miles(n.distance)] as [String: Any]
        }, "source": "NPS, Forest Service trails, RIDB"]
    }

    private func packList(_ a: [String: Any]) async throws -> [String: Any] {
        let s = try site(a)
        let acts = ((a["activities"] as? String) ?? "").split(separator: ",")
            .compactMap { PackActivity(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        let nights = min(max(a["nights"] as? Int ?? 2, 1), 21)
        async let c = ConditionsService.conditions(at: s.coordinate)
        async let w = try? RatingsAPI.wildlife(near: s.coordinate)
        let (cond, wild) = await (c, w)
        let lows = cond.nights.prefix(nights).map(\.low)
        let sections = PackPlanner.make(PackInputs(
            activities: acts.isEmpty ? PackActivity.favorites() : Set(acts), nights: nights, people: min(max(a["people"] as? Int ?? 2, 1), 12),
            coldestLow: lows.min(), warmestLow: lows.max(), siteHasWater: s.amenities.contains("water"),
            bearCountry: wild?.game.contains { $0.name.localizedCaseInsensitiveContains("bear") } ?? false))
        return ["sections": sections.map { sec in
            ["title": sec.title, "summary": sec.summary ?? "", "items": sec.items.prefix(8).map(\.title)] as [String: Any]
        }, "note": "The full list with sources and a checklist is under Make a pack list on the site card."]
    }

    private func planTrip(_ a: [String: Any]) async throws -> [String: Any] {
        guard let toName = a["to"] as? String else { throw ToolError("Where to?") }
        let from = try await resolvePlace(a["from"] as? String ?? "me")
        let to = try await resolvePlace(toName)
        var via: [TripPlace] = []
        for name in ((a["via"] as? String) ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
            let p = try await resolvePlace(name)
            via.append(TripPlace(name: p.name, coordinate: p.coordinate))
        }
        let trip = try await TripPlanner.makeTrip(
            from: TripPlace(name: from.name, coordinate: from.coordinate), to: TripPlace(name: to.name, coordinate: to.coordinate),
            via: via, startDate: .now, dailyMiles: min(max(a["daily_miles"] as? Int ?? 250, 80), 700),
            preferFree: a["free_only"] as? Bool ?? true, totalNights: a["nights"] as? Int, store: store, context: context)
        createdTrip = trip
        for s in trip.orderedStops where !mentioned.contains(s.siteID) { mentioned.append(s.siteID) }
        return ["saved_trip": trip.name, "nights": trip.totalNights,
                "camps": trip.orderedStops.map { ["site_id": $0.siteID, "name": $0.name, "nights": $0.nights] as [String: Any] },
                "note": "Saved in Trips. The person can open it from the chat."]
    }

    // MARK: Encoding

    /// "0.9", not 0.90000000000000002: JSONSerialization prints doubles at full precision.
    static func miles(_ d: Double) -> String { d < 10 ? String(format: "%.1f", d) : String(Int(d.rounded())) }

    /// Compact JSON, clipped so the on-device model's small window isn't swamped.
    static func json(_ value: Any, limit: Int = 3_000) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return #"{"error":"Couldn't encode the result."}"# }
        return text.count > limit ? String(text.prefix(limit)) + "…(clipped)" : text
    }
}
