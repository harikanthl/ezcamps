import Foundation
import Security
import Synchronization

// Bring-your-own-key AI, following the same pattern as ezLaw and Operator: providers reached through
// their OpenAI-compatible endpoints, keys in the Keychain, model lists from the Operator catalog worker.

/// Cloud model providers people can bring their own key for. Kimi, GLM and others are reachable
/// through OpenRouter or Custom.
nonisolated enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic, openai, gemini, grok, openrouter, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .grok: "xAI (Grok)"
        case .openrouter: "OpenRouter"
        case .custom: "Custom (OpenAI-compatible)"
        }
    }

    var shortTitle: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .openrouter: "OpenRouter"
        case .custom: "Custom"
        }
    }

    /// Where `…/chat/completions` and `…/models` live. Custom is set by the user.
    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openai: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .grok: "https://api.x.ai/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }

    var keyURL: URL? {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
        case .openai: URL(string: "https://platform.openai.com/api-keys")
        case .gemini: URL(string: "https://aistudio.google.com/apikey")
        case .grok: URL(string: "https://console.x.ai")
        case .openrouter: URL(string: "https://openrouter.ai/keys")
        case .custom: nil
        }
    }

    /// The key in the catalog's `providerModels`.
    var catalogKey: String? {
        switch self {
        case .anthropic: "anthropic"
        case .openai: "openai"
        case .gemini: "gemini"
        case .grok: "grok"
        case .openrouter, .custom: nil
        }
    }

    /// Example shown in the model-ID field.
    var modelIDPlaceholder: String {
        switch self {
        case .anthropic: "claude-…"
        case .openai: "gpt-…"
        case .gemini: "gemini-…"
        case .grok: "grok-…"
        case .openrouter: "vendor/model, e.g. moonshotai/kimi-k3"
        case .custom: "model-name"
        }
    }
}

/// A model to answer with: Apple's on-device model, or one provider's model id.
nonisolated struct ModelChoice: Codable, Hashable, Sendable {
    var provider: AIProvider?
    var modelID: String
    var label: String

    static let onDevice = ModelChoice(provider: nil, modelID: "apple.on-device", label: "On this iPhone (Apple)")

    var isOnDevice: Bool { provider == nil }

    // Same model whatever its display label (catalog vs. "(custom)").
    static func == (a: Self, b: Self) -> Bool { a.provider == b.provider && a.modelID == b.modelID }
    func hash(into h: inout Hasher) {
        h.combine(provider)
        h.combine(modelID)
    }
}

/// API keys live in the Keychain, on this device only, readable only while it's unlocked.
nonisolated enum APIKeyStore {
    static let service = "com.harikanthlingutla.ezcamps.apikeys"

    private static func query(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func key(for provider: AIProvider) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasKey(_ provider: AIProvider) -> Bool { !(key(for: provider) ?? "").isEmpty }

    /// Saves the key, or removes it when empty. Returns a readable error, or nil on success.
    @discardableResult
    static func setKey(_ key: String, for provider: AIProvider) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query(provider) as CFDictionary)
        guard !trimmed.isEmpty else { return nil }
        var attributes = query(provider)
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status != errSecSuccess else { return nil }
        return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Model lists per provider from the Operator catalog worker (`/provider-models`, refreshed every
/// six hours there). Cached on device with an ETag; a snapshot ships in the app for first launch
/// and offline use. Fetching it sends nothing about the user.
nonisolated struct ModelCatalog: Sendable {
    struct Entry: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var label: String
    }

    struct Payload: Codable, Sendable {
        var providerModels: [String: [Entry]]
        var updatedAt: String?
    }

    static let endpoint = URL(string: "https://catalog.operatorok.com/provider-models")!

    var cacheURL: URL { Self.cacheURL }
    static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "ai")
        return dir.appending(path: "provider-models.json")
    }()

    /// Decoded once and kept in memory: settings rows ask for model lists on every render, and
    /// re-reading and decoding the JSON file each time made the picker stutter.
    private static let current = Mutex<Payload?>(decode(try? Data(contentsOf: cacheURL)) ?? bundled)

    func models(for provider: AIProvider) -> [Entry] {
        guard let key = provider.catalogKey else { return [] }
        return Self.current.withLock { $0?.providerModels[key] } ?? []
    }

    var updatedAt: String? { Self.current.withLock { $0?.updatedAt } }

    /// Returns true when a newer list was downloaded.
    @discardableResult
    func refresh() async throws -> Bool {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        if let etag = try? String(contentsOf: cacheURL.appendingPathExtension("etag"), encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 304 else { return false }
        guard status == 200, let payload = Self.decode(data) else { throw ProviderHTTPError(status: status, body: "") }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        if let etag = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag") {
            try? etag.write(to: cacheURL.appendingPathExtension("etag"), atomically: true, encoding: .utf8)
        }
        Self.current.withLock { $0 = payload }
        return true
    }

    static func decode(_ data: Data?) -> Payload? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static let bundled: Payload? = {
        guard let url = Bundle.main.url(forResource: "provider-models", withExtension: "json") else { return nil }
        return decode(try? Data(contentsOf: url))
    }()
}

nonisolated struct ProviderHTTPError: LocalizedError {
    let status: Int
    let body: String

    var errorDescription: String? {
        switch status {
        case 401, 403: "The provider rejected this key (\(status))."
        case 404: "Model or endpoint not found (404). Check the model ID."
        case 429: "Rate limited or out of credit (429)."
        case -1: "The base URL must start with https:// so your key isn't sent unencrypted."
        case 0: "Couldn't reach the provider."
        default: "Provider error \(status)\(body.isEmpty ? "" : ": \(body.prefix(140))")"
        }
    }
}

/// One-shot chat completions over a provider's OpenAI-compatible endpoint.
nonisolated enum CloudChat {
    /// One credential, never two. Anthropic console keys go as `x-api-key` when listing models and as
    /// Bearer to its OpenAI-compatible chat endpoint; subscription tokens (`sk-ant-oat…`) always go as
    /// Bearer with the OAuth beta header. Same rules as ezLaw / Operator.
    static func authorize(_ request: inout URLRequest, key: String, provider: AIProvider, listing: Bool) {
        guard provider == .anthropic else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            return
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if key.hasPrefix("sk-ant-oat") {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        } else if listing {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    /// `…/path` under the provider's base URL, HTTPS only: the key rides in a header, and a custom
    /// base URL typed as http:// (or a typo'd scheme) would send it in the clear.
    static func endpoint(_ baseURL: String, _ path: String) throws -> URL {
        let root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + path), url.scheme?.lowercased() == "https", url.host() != nil else {
            throw ProviderHTTPError(status: -1, body: "")
        }
        return url
    }

    static func complete(system: String, user: String, model: String, provider: AIProvider,
                         baseURL: String, key: String) async throws -> String {
        let url = try endpoint(baseURL, "/chat/completions")
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request, key: key, provider: provider, listing: false)
        if provider == .openrouter { request.setValue("ezcamps", forHTTPHeaderField: "X-Title") }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderHTTPError(status: status, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw ProviderHTTPError(status: status, body: "Unexpected response")
        }
        if let text = message["content"] as? String { return text }
        // Some providers return content as parts.
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        throw ProviderHTTPError(status: status, body: "Empty response")
    }

    /// Checks a key by listing the provider's models: cheap and content-free.
    static func verify(key: String, provider: AIProvider, baseURL: String) async throws {
        let url = try endpoint(baseURL, "/models")
        var request = URLRequest(url: url, timeoutInterval: 15)
        authorize(&request, key: key, provider: provider, listing: true)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ProviderHTTPError(status: status, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
    }
}
