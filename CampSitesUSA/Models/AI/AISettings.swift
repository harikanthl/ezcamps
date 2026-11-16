import Foundation
import Observation

/// Features that use AI. Each picks its own model in Settings, so a quick task can use a small, cheap
/// model while a bigger one can use a frontier model.
enum AIFeature: String, CaseIterable, Identifiable {
    case planTrip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planTrip: "Plan with AI"
        }
    }

    var symbol: String {
        switch self {
        case .planTrip: "sparkles"
        }
    }

    var section: String {
        switch self {
        case .planTrip: "Trips"
        }
    }

    var explainer: String {
        switch self {
        case .planTrip: "Turns a request like “SF to Moab via Zion, 5 nights, free sites” into a route. Campsites always come from ezcamp' open data, never from the model."
        }
    }
}

/// Which model each feature uses, which providers have keys, and custom model IDs people typed.
/// Keys live in the Keychain (APIKeyStore); everything else in UserDefaults.
@Observable
final class AISettings {
    private let defaults = UserDefaults.standard
    let catalog = ModelCatalog()

    /// Bumps when keys, custom models or the catalog change, so views re-read them.
    private(set) var version = 0

    /// Keychain lookups are slow-ish and views ask on every render; cache them, drop on any change.
    @ObservationIgnored private var keyCache: [AIProvider: Bool] = [:]

    var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: "ai.customBaseURL") }
    }

    init() {
        customBaseURL = defaults.string(forKey: "ai.customBaseURL") ?? ""
    }

    // MARK: Per-feature model

    func model(for feature: AIFeature) -> ModelChoice {
        _ = version
        guard let data = defaults.data(forKey: "ai.model.\(feature.rawValue)"),
              let choice = try? JSONDecoder().decode(ModelChoice.self, from: data) else { return .onDevice }
        // A model whose key was removed falls back to on-device.
        if let p = choice.provider, !hasKey(p) { return .onDevice }
        return choice
    }

    func setModel(_ choice: ModelChoice, for feature: AIFeature) {
        if let data = try? JSONEncoder().encode(choice) { defaults.set(data, forKey: "ai.model.\(feature.rawValue)") }
        version += 1
    }

    // MARK: Keys

    func hasKey(_ provider: AIProvider) -> Bool {
        _ = version
        if let hit = keyCache[provider] { return hit }
        let has = APIKeyStore.hasKey(provider)
        keyCache[provider] = has
        return has
    }

    var hasAnyKey: Bool { AIProvider.allCases.contains(where: hasKey) }

    /// Saves (or clears) a key. The first key makes its provider's first model the default for every
    /// feature still on-device, so adding a key "just works".
    func setKey(_ key: String, for provider: AIProvider) -> String? {
        let error = APIKeyStore.setKey(key, for: provider)
        keyCache[provider] = nil
        version += 1
        if error == nil, !key.isEmpty, let first = models(for: provider).first {
            for f in AIFeature.allCases where model(for: f).isOnDevice { setModel(first, for: f) }
        }
        return error
    }

    func verify(_ provider: AIProvider) async throws {
        guard let key = APIKeyStore.key(for: provider) else { throw ProviderHTTPError(status: 401, body: "") }
        try await CloudChat.verify(key: key, provider: provider, baseURL: baseURL(for: provider))
    }

    func baseURL(for provider: AIProvider) -> String {
        provider == .custom ? customBaseURL : provider.defaultBaseURL
    }

    // MARK: Custom model IDs (any provider)

    func customModels(for provider: AIProvider) -> [String] {
        _ = version
        return defaults.stringArray(forKey: "ai.customModels.\(provider.rawValue)") ?? []
    }

    /// Adds a model ID the user typed for this provider (newest first) and returns its choice.
    @discardableResult
    func addCustomModel(_ id: String, for provider: AIProvider) -> ModelChoice? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var list = customModels(for: provider).filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        defaults.set(Array(list.prefix(10)), forKey: "ai.customModels.\(provider.rawValue)")
        version += 1
        return ModelChoice(provider: provider, modelID: trimmed, label: trimmed)
    }

    func removeCustomModel(_ id: String, for provider: AIProvider) {
        defaults.set(customModels(for: provider).filter { $0 != id }, forKey: "ai.customModels.\(provider.rawValue)")
        for f in AIFeature.allCases where model(for: f) == ModelChoice(provider: provider, modelID: id, label: id) {
            setModel(.onDevice, for: f)
        }
        version += 1
    }

    // MARK: Lists

    /// Custom IDs first (the user typed them on purpose), then the catalog, Claude led by Sonnet.
    func models(for provider: AIProvider) -> [ModelChoice] {
        _ = version
        var entries = catalog.models(for: provider)
        if provider == .anthropic, let i = entries.firstIndex(where: { $0.id.contains("sonnet") }) {
            entries.insert(entries.remove(at: i), at: 0)
        }
        let custom = customModels(for: provider).map { ModelChoice(provider: provider, modelID: $0, label: "\($0) (custom)") }
        let catalogChoices = entries.map { ModelChoice(provider: provider, modelID: $0.id, label: $0.label) }
            .filter { c in !custom.contains { $0.modelID == c.modelID } }
        return custom + catalogChoices
    }

    /// Picker sections: on-device, then up to eight models from each provider with a key.
    func pickerSections(current: ModelChoice) -> [(provider: AIProvider?, models: [ModelChoice])] {
        _ = version
        var sections: [(AIProvider?, [ModelChoice])] = [(nil, [.onDevice])]
        for provider in AIProvider.allCases where hasKey(provider) {
            var list = Array(models(for: provider).prefix(8))
            if current.provider == provider, !list.contains(where: { $0.modelID == current.modelID }) { list.insert(current, at: 0) }
            if !list.isEmpty { sections.append((provider, list)) }
        }
        return sections
    }

    func refreshCatalog() async {
        if (try? await catalog.refresh()) == true { version += 1 }
    }
}
