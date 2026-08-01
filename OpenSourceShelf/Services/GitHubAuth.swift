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

    static var token: String? {
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

    /// Saves the token, replacing any existing one. An empty string removes it.
    static func setToken(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeToken()
            return
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func removeToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
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
