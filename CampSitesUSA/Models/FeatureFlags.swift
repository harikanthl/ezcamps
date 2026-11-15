/// Features that are built but not ready to ship.
enum FeatureFlags {
    /// Offline state packs (Saved › Offline maps, trip "Download for offline"). Parked for a later
    /// version: plan is to host our own PAD-US vector packs instead of bulk-downloading BLM tiles,
    /// and to add a near-boundary warning to offline "Can I camp here?". See docs/RESEARCH.md.
    static let offlinePacks = false
}
