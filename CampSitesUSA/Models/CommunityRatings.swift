import Foundation
import SwiftData
import Security
import AuthenticationServices
import Observation

// Shared ratings: everyone's ratings for a site, from the ezcamps ratings Worker (server/ratings).
// Reading needs no account. Sharing your own ratings needs Sign in with Apple; the server keeps no
// name or email, and ratings show up anonymously.

// MARK: - Wire types

nonisolated struct CommunitySummary: Codable, Sendable, Equatable {
    var score: Double?
    var count: Int
    var verifiedCount: Int
    var latestVisit: String?
}

nonisolated struct CommunityRating: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var visitDate: String
    var rating: Int
    var tags: [String]
    var note: String
    var verified: Bool
    var carrier: String?
    var signal: Int?
    var mine: Bool

    var date: Date? { RatingsAPI.day(visitDate) }
}

nonisolated struct RecentTag: Codable, Sendable, Equatable {
    var tag: String
    var count: Int
    var latest: String
}

nonisolated struct SiteCommunity: Codable, Sendable, Equatable {
    var summary: CommunitySummary
    var recentTags: [RecentTag]
    var ratings: [CommunityRating]
}

// MARK: - API

nonisolated enum RatingsAPI {
    static let base = URL(string: "https://ezcamps-ratings.harikanth-ai.workers.dev")!

    struct ServerError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    static func site(_ id: String, token: String?) async throws -> SiteCommunity {
        let path = "/v1/sites/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? id)/ratings"
        return try await send("GET", path, token: token)
    }

    static func signIn(identityToken: String) async throws -> String {
        struct Out: Decodable { let token: String }
        let out: Out = try await send("POST", "/v1/auth/apple", body: ["identityToken": identityToken])
        return out.token
    }

    static func upload(_ v: UploadRating, id: String, token: String) async throws -> String {
        struct Out: Decodable { let id: String }
        let out: Out = try await send("PUT", "/v1/ratings/\(id)", token: token, body: v)
        return out.id
    }

    static func delete(id: String, token: String) async throws {
        let _: Empty = try await send("DELETE", "/v1/ratings/\(id)", token: token)
    }

    static func report(id: String, reason: String, token: String) async throws {
        let _: Empty = try await send("POST", "/v1/ratings/\(id)/report", token: token, body: ["reason": reason])
    }

    static func deleteAccount(token: String) async throws {
        let _: Empty = try await send("DELETE", "/v1/account", token: token)
    }

    struct UploadRating: Encodable, Sendable {
        var siteId: String
        var visitDate: String
        var rating: Int
        var tags: [String]
        var note: String
        var verified: Bool
        var carrier: String?
        var signal: Int?
    }

    private struct Empty: Decodable {}
    private struct ErrorBody: Decodable { let error: String }

    private static func send<T: Decodable>(_ method: String, _ path: String, token: String? = nil,
                                           body: (any Encodable & Sendable)? = nil) async throws -> T {
        var req = URLRequest(url: URL(string: base.absoluteString + path)!, timeoutInterval: 20)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Ratings server error (\(status))."
            throw ServerError(status: status, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}

// MARK: - Session storage

/// The ratings session token and the Apple user id, in the Keychain (this device only).
nonisolated enum RatingsKeychain {
    private static let service = "com.harikanthlingutla.ezcamps.ratings"

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String?, _ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var a = query(account)
        a[kSecValueData as String] = Data(value.utf8)
        a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(a as CFDictionary, nil)
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecUseDataProtectionKeychain as String: true]
    }
}

// MARK: - Account and sync

/// Signed-in state, the "share my ratings" choice, and uploading local ratings.
@Observable
final class CommunityAccount {
    private(set) var isSignedIn: Bool
    private(set) var syncing = false
    private(set) var lastError: String?
    /// Bumps after an upload or delete so site cards refetch community ratings.
    private(set) var revision = 0

    /// Upload my ratings (on by default once signed in). Off keeps them on this iPhone only.
    var shareRatings: Bool {
        didSet { UserDefaults.standard.set(shareRatings, forKey: "ratings.share") }
    }

    var token: String? { RatingsKeychain.get("session") }

    init() {
        isSignedIn = RatingsKeychain.get("session") != nil
        shareRatings = UserDefaults.standard.object(forKey: "ratings.share") as? Bool ?? true
    }

    /// Completes Sign in with Apple: trades Apple's identity token for an ezcamps session.
    func completeSignIn(_ result: Result<ASAuthorization, any Error>, context: ModelContext) async {
        lastError = nil
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { lastError = error.localizedDescription }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.identityToken, let jwt = String(data: data, encoding: .utf8) else {
                lastError = "Sign in with Apple didn't return a token."
                return
            }
            do {
                let token = try await RatingsAPI.signIn(identityToken: jwt)
                RatingsKeychain.set(token, "session")
                RatingsKeychain.set(cred.user, "appleUser")
                isSignedIn = true
                await sync(context: context)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func signOut() {
        RatingsKeychain.set(nil, "session")
        RatingsKeychain.set(nil, "appleUser")
        isSignedIn = false
        revision += 1
    }

    /// Deletes the account and every shared rating on the server. Ratings stay on this iPhone,
    /// marked unsynced, so signing in again can share them again.
    func deleteAccount(context: ModelContext) async -> Bool {
        guard let token else { return false }
        do {
            try await RatingsAPI.deleteAccount(token: token)
            for v in (try? context.fetch(FetchDescriptor<Visit>())) ?? [] { v.remoteID = nil; v.synced = false }
            signOut()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Signs out if the person revoked ezcamps in Settings › Apple ID (Apple asks apps to check on launch).
    func checkAppleCredential() async {
        guard isSignedIn, let user = RatingsKeychain.get("appleUser") else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: user)
        if state == .revoked || state == .notFound { signOut() }
    }

    /// Uploads ratings that aren't on the server yet (or changed). Safe to call any time.
    func sync(context: ModelContext) async {
        guard isSignedIn, shareRatings, !syncing, let token else { return }
        let pending = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { !$0.synced }))) ?? []
        guard !pending.isEmpty else { return }
        syncing = true
        defer { syncing = false }
        lastError = nil
        upload: for v in pending {
            let id = v.remoteID ?? UUID().uuidString.lowercased()
            let body = RatingsAPI.UploadRating(siteId: v.siteID, visitDate: v.visitDay, rating: v.rating, tags: v.tags,
                                               note: v.note, verified: v.verified, carrier: v.carrier, signal: v.signal)
            do {
                v.remoteID = try await RatingsAPI.upload(body, id: id, token: token)
                v.synced = true
            } catch let e as RatingsAPI.ServerError where e.status == 401 {
                signOut()  // session expired or account gone: ask to sign in again
                lastError = "Sign in again to share your ratings."
                break upload
            } catch let e as RatingsAPI.ServerError where e.status == 400 || e.status == 409 {
                v.synced = true  // the server will never take this one (e.g. a duplicate night); don't retry forever
                lastError = e.message
            } catch {
                lastError = error.localizedDescription
                break upload  // offline: try again later
            }
        }
        try? context.save()
        revision += 1
    }

    /// Removes a rating from the server before it's deleted on the phone.
    func deleteRemote(_ visit: Visit) async {
        guard let id = visit.remoteID, let token else { return }
        try? await RatingsAPI.delete(id: id, token: token)
        revision += 1
    }

    func report(_ rating: CommunityRating, reason: String) async -> Bool {
        guard let token else { return false }
        do {
            try await RatingsAPI.report(id: rating.id, reason: reason, token: token)
            revision += 1
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
