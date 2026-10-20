import Foundation
import Security

/// Optional GitHub personal access token, stored in the macOS Keychain.
///
/// Without a token GitHub allows ~60 unauthenticated API requests per hour per
/// IP address — easy to exhaust with a few bulk imports. A token raises that to
/// 5,000/hour and lets Quick Capture see the user's own private repos. The app
/// never writes the token anywhere except the Keychain.
enum GitHubAuth {
    private static let service = "reshelf.github-token"
    private static let account = "github"

    /// The token is read from the Keychain once and kept in memory: a refresh
    /// sends hundreds of requests from several threads at once, and a Keychain
    /// read per request serialized them (and, for a differently signed build,
    /// raised one access prompt per request). `setToken` / `removeToken` keep
    /// the cache in step. A declined Keychain prompt caches "no token" for the
    /// rest of the session instead of asking again.
    private static let cacheLock = NSLock()
    private static var cachedToken: String?? = nil

    static var token: String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cachedToken { return cached }
        let value = readKeychain()
        cachedToken = .some(value)
        return value
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static var hasToken: Bool { token != nil }

    /// A Keychain write that didn't work, with the status it returned.
    struct KeychainError: LocalizedError, Equatable {
        let status: OSStatus
        let removing: Bool

        var errorDescription: String? {
            removing
                ? "Couldn't remove the token from the Keychain (error \(status))."
                : "Couldn't save the token to the Keychain (error \(status))."
        }
    }

    /// Saves the token, replacing any existing one. An empty string removes it.
    /// Throws when the Keychain write fails; the in-memory copy changes only
    /// after a write that worked, so Settings never says "Saved" for a token
    /// that isn't there.
    static func setToken(_ raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try removeToken() }
        let status = saveKeychain(trimmed, service: service, account: account)
        guard status == errSecSuccess else { throw KeychainError(status: status, removing: false) }
        cacheLock.lock()
        cachedToken = .some(trimmed)
        cacheLock.unlock()
    }

    /// Removes the token. A token that was never stored counts as removed.
    static func removeToken() throws {
        let status = deleteKeychain(service: service, account: account)
        guard status == errSecSuccess else { throw KeychainError(status: status, removing: true) }
        cacheLock.lock()
        cachedToken = .some(nil)
        cacheLock.unlock()
    }

    /// Writes one generic-password item (update, or add when missing).
    /// `service` is a parameter so tests can use a throwaway item.
    static func saveKeychain(_ value: String, service: String, account: String) -> OSStatus {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var add = base
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil)
    }

    /// Deletes one generic-password item; "not found" counts as success.
    static func deleteKeychain(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }

    /// Adds the Authorization header when a token is stored; no-op otherwise.
    static func authorize(_ request: inout URLRequest) {
        guard let token else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Result of asking GitHub what the current rate limit is — used by the
    /// Settings "Test" button to confirm a saved token actually works.
    enum TokenCheck {
        case working(limitPerHour: Int)
        case rejected
        case failed(String)
    }

    /// Calls `/rate_limit` (which itself never counts against the limit) with
    /// the stored token attached.
    static func checkToken() async -> TokenCheck {
        var request = URLRequest(url: URL(string: "https://api.github.com/rate_limit")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        authorize(&request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("No response from GitHub.")
            }
            if http.statusCode == 401 { return .rejected }
            guard http.statusCode == 200 else {
                return .failed("GitHub returned HTTP \(http.statusCode).")
            }
            struct RateLimitResponse: Codable {
                struct Resources: Codable {
                    struct Core: Codable { let limit: Int }
                    let core: Core
                }
                let resources: Resources
            }
            guard let decoded = try? JSONDecoder().decode(RateLimitResponse.self, from: data) else {
                return .failed("Couldn't read GitHub's response.")
            }
            return .working(limitPerHour: decoded.resources.core.limit)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
