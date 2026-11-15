import Foundation
import CoreLocation

/// "Can I camp here?" Asks the BLM Surface Management Agency service who manages the land
/// at a point, then maps the agency to a plain-language answer. Guidance, not legal advice:
/// closures, fire restrictions and local orders always win.
nonisolated struct LandCheck: Identifiable, Sendable {
    enum Verdict: Sendable { case likelyYes, check, likelyNo }

    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let agencyCode: String
    let agencyName: String
    let unitName: String?
    let verdict: Verdict
    let summary: String
    let rules: [String]

    static func lookup(_ c: CLLocationCoordinate2D) async throws -> LandCheck {
        var comps = URLComponents(string: PublicLandsService.base + "/identify")!
        let d = 0.01
        comps.queryItems = [
            .init(name: "geometry", value: "\(c.longitude),\(c.latitude)"),
            .init(name: "geometryType", value: "esriGeometryPoint"),
            .init(name: "sr", value: "4326"),
            .init(name: "layers", value: "all:0"),
            .init(name: "tolerance", value: "0"),
            .init(name: "mapExtent", value: "\(c.longitude - d),\(c.latitude - d),\(c.longitude + d),\(c.latitude + d)"),
            .init(name: "imageDisplay", value: "400,400,96"),
            .init(name: "returnGeometry", value: "false"),
            .init(name: "f", value: "json"),
        ]
        var req = URLRequest(url: comps.url!, timeoutInterval: 15)
        req.setValue("ezcamps-ios", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONDecoder().decode(IdentifyResponse.self, from: data)
        let attrs = decoded.results.first?.attributes ?? [:]
        let code = attrs["ADMIN_AGENCY_CODE"].flatMap { $0 == "Null" ? nil : $0 } ?? "UND"
        let unit = attrs["ADMIN_UNIT_NAME"].flatMap { $0 == "Null" || $0.isEmpty ? nil : $0 }
        return make(code: code, unit: unit, at: c)
    }

    static func make(code: String, unit: String?, at c: CLLocationCoordinate2D) -> LandCheck {
        let info: (String, Verdict, String, [String]) = switch code {
        case "BLM":
            ("Bureau of Land Management", .likelyYes, "Dispersed camping is generally allowed on BLM land.",
             ["Stay up to 14 days in one spot, then move at least 25 miles (varies by field office).",
              "Use existing campsites and roads. Don't drive off-route.",
              "Pack out all trash. Check for fire restrictions."])
        case "USFS":
            ("US Forest Service", .likelyYes, "Dispersed camping is usually allowed in national forests.",
             ["Typical limit is 14–16 days. Check the forest's rules.",
              "Drive only on roads shown on the Motor Vehicle Use Map (MVUM).",
              "Camp 100–200 ft from water. Check for fire restrictions."])
        case "NPS":
            ("National Park Service", .likelyNo, "Camping is only allowed in designated campgrounds or with a backcountry permit.",
             ["Look for park campgrounds nearby, or get a backcountry permit from the park."])
        case "FWS":
            ("US Fish & Wildlife Service", .likelyNo, "Camping is usually not allowed on wildlife refuges.",
             ["A few refuges allow it in designated sites. Check with the refuge."])
        case "BOR":
            ("Bureau of Reclamation", .check, "Camping is often allowed in designated areas around reservoirs.",
             ["Check posted rules or the managing recreation agency."])
        case "DOD":
            ("Department of Defense", .likelyNo, "Military land. Camping is not allowed.", [])
        case "BIA":
            ("Tribal land", .likelyNo, "Tribal land. Camping needs permission from the tribe.",
             ["Some tribes sell camping or recreation permits. Contact the tribal office."])
        case "ST", "SDC", "SDNR", "SDOL", "SFW", "SPR", "SDA", "OTHST":
            ("State land", .check, "State land. Rules vary a lot by state and agency.",
             ["State trust land often requires a recreation permit.",
              "State parks and wildlife areas usually limit camping to designated sites."])
        case "LG":
            ("Local government", .check, "City or county land. Usually camping only in designated campgrounds.", [])
        case "PVT":
            ("Private land", .likelyNo, "Private land. Camping needs the owner's permission.", [])
        default:
            ("Unknown or private", .check, "We couldn't confirm who manages this land. Assume private unless posted otherwise.", [])
        }
        return LandCheck(coordinate: c, agencyCode: code, agencyName: info.0, unitName: unit,
                         verdict: info.1, summary: info.2, rules: info.3)
    }

    private struct IdentifyResponse: Decodable {
        struct Result: Decodable {
            let attributes: [String: String]
            init(from decoder: Decoder) throws {
                // ArcGIS usually sends strings, but tolerate numbers and nulls.
                let raw = try decoder.container(keyedBy: Key.self)
                    .nestedContainer(keyedBy: Key.self, forKey: Key("attributes"))
                var out: [String: String] = [:]
                for k in raw.allKeys {
                    if let s = try? raw.decode(String.self, forKey: k) { out[k.stringValue] = s }
                    else if let d = try? raw.decode(Double.self, forKey: k) { out[k.stringValue] = String(d) }
                }
                attributes = out
            }
        }
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ s: String) { stringValue = s }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        let results: [Result]
    }
}

nonisolated enum PublicLandsService {
    static let base = "https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_Cached_without_PriUnk/MapServer"
}
