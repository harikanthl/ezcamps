import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the model understood from a trip request. The model only fills this in; the route and the
/// campsites always come from TripPlanner and ezcamps' own data, so it can't invent a campground.
nonisolated struct TripIntent: Codable, Equatable, Sendable {
    var from: String?
    var to: String?
    var via: [String] = []
    var startDate: String?        // yyyy-MM-dd
    var nights: Int?
    var maxDrivingHours: Double?
    var maxDrivingMiles: Int?
    var freeOnly: Bool?

    /// Daily driving budget in miles (hours × ~55 mph on mixed roads), default 250.
    var dailyMiles: Int {
        if let m = maxDrivingMiles, m > 0 { return min(max(m, 80), 700) }
        if let h = maxDrivingHours, h > 0 { return min(max(Int(h * 55), 80), 700) }
        return 250
    }

    var start: Date? {
        guard let s = startDate else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    var isUsable: Bool { !(to ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
}

enum TripAIError: LocalizedError {
    case onDeviceUnavailable(String)
    case missingKey(AIProvider)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable(let why): "Apple's on-device model isn't available (\(why)). Add an API key in Settings › AI, or plan the trip manually."
        case .missingKey(let p): "Add a \(p.shortTitle) API key in Settings › AI."
        case .unreadable: "The model's answer didn't make sense. Try rephrasing, or pick a different model in Settings › AI."
        }
    }
}

enum TripAI {
    static func instructions(today: Date = .now) -> String {
        let day = today.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let weekday = today.formatted(.dateTime.weekday(.wide))
        return """
        You turn a camping road-trip request in the USA into structured fields. Today is \(weekday), \(day).
        Fields:
        - from: starting place as a searchable name (city, park or address). Empty if not given (the app uses the person's location).
        - to: destination as a searchable name. Required if any destination is mentioned.
        - via: places to pass through or stay at on the way, in order. Empty list if none.
        - startDate: yyyy-MM-dd. Resolve relative dates ("next Friday", "this weekend") from today. Empty if not given.
        - nights: total nights camping, or 0 if not given.
        - maxDrivingHours: most hours of driving per day, or 0 if not given.
        - maxDrivingMiles: most miles per day, or 0 if not given.
        - freeOnly: true if they want free, dispersed or boondocking sites; false otherwise.
        Never invent campsites. Only extract what the person said.
        """
    }

    /// Returns the intent and whether a model read it (false = pattern fallback).
    static func understand(_ text: String, using choice: ModelChoice, settings: AISettings) async throws -> (TripIntent, Bool) {
        if choice.isOnDevice {
            do {
                return (try await onDevice(text), true)
            } catch {
                // No usable on-device model: read the common phrasing without AI rather than fail.
                return (readWithoutAI(text), false)
            }
        }
        return (try await understandWithModel(text, using: choice, settings: settings), true)
    }

    private static func understandWithModel(_ text: String, using choice: ModelChoice, settings: AISettings) async throws -> TripIntent {
        if let provider = choice.provider {
            guard let key = APIKeyStore.key(for: provider), !key.isEmpty else { throw TripAIError.missingKey(provider) }
            let system = instructions() + """

            Reply with only a JSON object with exactly these keys: from, to, via, startDate, nights, maxDrivingHours, maxDrivingMiles, freeOnly. No prose, no code fences.
            """
            let reply = try await CloudChat.complete(system: system, user: text, model: choice.modelID, provider: provider,
                                                     baseURL: settings.baseURL(for: provider), key: key)
            return try parseJSON(reply)
        }
        return try await onDevice(text)
    }

    /// Pulls the first JSON object out of a reply (tolerates code fences or a sentence around it).
    static func parseJSON(_ reply: String) throws -> TripIntent {
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let obj = try? JSONSerialization.jsonObject(with: Data(reply[open...close].utf8)) as? [String: Any]
        else { throw TripAIError.unreadable }
        func str(_ k: String) -> String? {
            guard let s = obj[k] as? String else { return nil }
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t.lowercased() == "null" ? nil : t
        }
        func num(_ k: String) -> Double? {
            if let d = obj[k] as? Double { return d > 0 ? d : nil }
            if let s = obj[k] as? String, let d = Double(s) { return d > 0 ? d : nil }
            return nil
        }
        var intent = TripIntent()
        intent.from = str("from")
        intent.to = str("to")
        intent.via = (obj["via"] as? [String])?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        intent.startDate = str("startDate")
        intent.nights = num("nights").map { Int($0) }
        intent.maxDrivingHours = num("maxDrivingHours")
        intent.maxDrivingMiles = num("maxDrivingMiles").map { Int($0) }
        intent.freeOnly = obj["freeOnly"] as? Bool ?? (obj["freeOnly"] as? String).map { $0.lowercased() == "true" }
        return intent
    }

    // MARK: Without AI

    /// Reads the common phrasing with plain pattern matching, for when no model is available:
    /// "A to B via C and D, 5 nights, free sites, under 3 hours a day, leaving next Friday".
    static func readWithoutAI(_ text: String, today: Date = .now) -> TripIntent {
        var intent = TripIntent()
        let t = text.replacingOccurrences(of: "\n", with: " ")
        func match(_ pattern: String) -> [String]? {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = rx.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
            return (0..<m.numberOfRanges).map { i in
                Range(m.range(at: i), in: t).map { String(t[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            }
        }
        // Places: "[from] A to B [via C]" up to the first comma or detail keyword.
        let stop = "(?=,|\\.|;| for | leaving| starting| on | next | this | with | under | in \\d|$)"
        if let m = match("(?:^|from\\s+)([A-Za-z .'’-]+?)\\s+to\\s+([A-Za-z .'’-]+?)(?:\\s+via\\s+([A-Za-z .,'’-]+?))?" + stop) {
            let from = m[1].replacingOccurrences(of: "^(?i)(drive|trip|road trip|go|going)\\s+(from\\s+)?", with: "", options: .regularExpression)
            intent.from = from.isEmpty ? nil : from
            intent.to = m[2].isEmpty ? nil : m[2]
            if m.count > 3, !m[3].isEmpty {
                intent.via = m[3].components(separatedBy: CharacterSet(charactersIn: ",")).flatMap { $0.components(separatedBy: " and ") }
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        } else if let m = match("(?:to|toward|towards)\\s+([A-Za-z .'’-]+?)" + stop) {
            intent.to = m[1]
        }
        if let m = match("(\\d+)\\s*nights?") { intent.nights = Int(m[1]) }
        else if t.range(of: "weekend", options: .caseInsensitive) != nil { intent.nights = 2 }
        if let m = match("(\\d+(?:\\.\\d+)?)\\s*(?:hours?|hrs?|h)\\b") { intent.maxDrivingHours = Double(m[1]) }
        if let m = match("(\\d{2,3})\\s*(?:miles?|mi)\\b") { intent.maxDrivingMiles = Int(m[1]) }
        intent.freeOnly = t.range(of: "free|boondock|dispersed|blm", options: [.caseInsensitive, .regularExpression]) != nil
        intent.startDate = relativeDate(in: t, today: today)
        return intent
    }

    /// "today", "tomorrow", "this weekend", "next Friday", "on Friday".
    static func relativeDate(in text: String, today: Date) -> String? {
        let cal = Calendar.current
        let lower = text.lowercased()
        var date: Date?
        if lower.contains("tomorrow") { date = cal.date(byAdding: .day, value: 1, to: today) }
        else if lower.contains("today") || lower.contains("tonight") { date = today }
        else if lower.contains("weekend") {
            date = cal.nextDate(after: today, matching: DateComponents(weekday: 6), matchingPolicy: .nextTime)
        } else {
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            for (i, n) in names.enumerated() where lower.contains(n) {
                // "Friday" or "next Friday": the coming one. The card shows the date so it's easy to fix.
                let d = cal.nextDate(after: today, matching: DateComponents(weekday: i + 1), matchingPolicy: .nextTime)
                date = d
                break
            }
        }
        return date.map { $0.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    }

    // MARK: On-device (Apple Foundation Models)

    static var onDeviceStatus: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "this iPhone doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled): return "Apple Intelligence is turned off in Settings"
        case .unavailable(.modelNotReady): return "the model is still downloading"
        case .unavailable: return "unavailable"
        }
        #else
        return "not supported on this iOS version"
        #endif
    }

    private static func onDevice(_ text: String) async throws -> TripIntent {
        #if canImport(FoundationModels)
        if let why = onDeviceStatus { throw TripAIError.onDeviceUnavailable(why) }
        let session = LanguageModelSession(instructions: instructions())
        let g = try await session.respond(to: text, generating: GeneratedTripIntent.self).content
        var intent = TripIntent()
        intent.from = g.from.isEmpty ? nil : g.from
        intent.to = g.to.isEmpty ? nil : g.to
        intent.via = g.via.filter { !$0.isEmpty }
        intent.startDate = g.startDate.isEmpty ? nil : g.startDate
        intent.nights = g.nights > 0 ? g.nights : nil
        intent.maxDrivingHours = g.maxDrivingHours > 0 ? g.maxDrivingHours : nil
        intent.maxDrivingMiles = g.maxDrivingMiles > 0 ? g.maxDrivingMiles : nil
        intent.freeOnly = g.freeOnly
        return intent
        #else
        throw TripAIError.onDeviceUnavailable("not supported on this iOS version")
        #endif
    }
}

#if canImport(FoundationModels)
@Generable
struct GeneratedTripIntent {
    @Guide(description: "Starting place (city, park or address). Empty if not given.")
    var from: String
    @Guide(description: "Destination (city, park or address).")
    var to: String
    @Guide(description: "Places to pass through or stay at on the way, in order. Empty if none.")
    var via: [String]
    @Guide(description: "Start date as yyyy-MM-dd, resolved from today. Empty if not given.")
    var startDate: String
    @Guide(description: "Total nights camping, 0 if not given.")
    var nights: Int
    @Guide(description: "Most hours of driving per day, 0 if not given.")
    var maxDrivingHours: Double
    @Guide(description: "Most miles of driving per day, 0 if not given.")
    var maxDrivingMiles: Int
    @Guide(description: "True if they want free, dispersed or boondocking sites.")
    var freeOnly: Bool
}
#endif
