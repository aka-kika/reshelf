import Foundation
import Security

enum AIProviderCredentialStore {
    private static let service = "com.kika.opensourceshelf.ai-providers"

    static func saveAPIKey(_ key: String, for provider: AIProviderKind) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.requiresAPIKey else { return }

        if trimmed.isEmpty {
            deleteAPIKey(for: provider)
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw AIProviderCredentialError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AIProviderCredentialError.keychainWriteFailed(status)
        }
    }

    static func loadAPIKey(for provider: AIProviderKind) -> String? {
        guard provider.requiresAPIKey else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func deleteAPIKey(for provider: AIProviderKind) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasAPIKey(for provider: AIProviderKind) -> Bool {
        loadAPIKey(for: provider) != nil
    }
}

enum AIProviderCredentialError: LocalizedError {
    case encodingFailed
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the API key."
        case let .keychainWriteFailed(status):
            return "Keychain save failed (status \(status))."
        }
    }
}
