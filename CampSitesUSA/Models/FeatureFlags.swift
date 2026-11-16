import Foundation

/// Features that are built but not ready to ship.
enum FeatureFlags {
    /// Offline state packs (Saved › Offline maps, trip "Download for offline"). Parked for a later
    /// version: plan is to host our own PAD-US vector packs instead of bulk-downloading BLM tiles,
    /// and to add a near-boundary warning to offline "Can I camp here?". See docs/RESEARCH.md.
    static let offlinePacks = false
}

#if DEBUG
/// Launch-argument testing aids (`-debugAIPrompt "…"`, `-debugPlanTrip YES`, …). Each one fires once
/// per launch: views reappear (back from a trip, tab switches), and re-reading the argument there
/// would repeat the action, e.g. plan another trip every time you come back to the list.
enum DebugLaunch {
    private static var used: Set<String> = []

    /// The argument's value the first time it's asked for, nil after that (or when it isn't set).
    static func string(_ key: String) -> String? {
        guard !used.contains(key), let v = UserDefaults.standard.string(forKey: key) else { return nil }
        used.insert(key)
        return v
    }

    /// True the first time a boolean argument is asked for, false after that.
    static func flag(_ key: String) -> Bool {
        guard !used.contains(key), UserDefaults.standard.bool(forKey: key) else { return false }
        used.insert(key)
        return true
    }

    /// Whether the argument was passed at all (doesn't use it up).
    static func isSet(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) != nil }

    /// True only the first time `token` is seen this launch.
    static func once(_ token: String) -> Bool { used.insert("once." + token).inserted }
}
#endif
