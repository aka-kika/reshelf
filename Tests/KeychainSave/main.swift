import Foundation
import Security

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

// Throwaway item, unique per run. Never the app's "reshelf.github-token".
let service = "reshelf-test.keychain-save.\(UUID().uuidString)"
let account = "test"

func read() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

check("add a new item returns success",
      GitHubAuth.saveKeychain("first", service: service, account: account) == errSecSuccess)
check("the item holds the value", read() == "first")
check("update an existing item returns success",
      GitHubAuth.saveKeychain("second", service: service, account: account) == errSecSuccess)
check("the item holds the new value", read() == "second")
check("delete returns success",
      GitHubAuth.deleteKeychain(service: service, account: account) == errSecSuccess)
check("the item is gone", read() == nil)
check("deleting a missing item counts as success",
      GitHubAuth.deleteKeychain(service: service, account: account) == errSecSuccess)

// A failed write: the error Settings shows instead of "Saved".
let saveError = GitHubAuth.KeychainError(status: errSecAuthFailed, removing: false)
check("save failure message",
      saveError.localizedDescription == "Couldn't save the token to the Keychain (error -25293).")
let removeError = GitHubAuth.KeychainError(status: errSecAuthFailed, removing: true)
check("remove failure message",
      removeError.localizedDescription == "Couldn't remove the token from the Keychain (error -25293).")

// Belt and braces: leave nothing behind.
_ = GitHubAuth.deleteKeychain(service: service, account: account)
if failures > 0 { print("\(failures) failed"); exit(1) }
print("KeychainSave: all passed")
