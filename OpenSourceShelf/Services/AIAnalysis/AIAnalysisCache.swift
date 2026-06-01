import Foundation
import CryptoKit

enum AIAnalysisCache {
    static let promptVersion = "stage6-v1"
    static let defaultBaseURL = "http://localhost:11434"
    static let defaultModel = "llama3.2:3b"

    static var baseURL: String {
        let stored = UserDefaults.standard.string(forKey: "reshelf.ollamaBaseURL") ?? ""
        return stored.isEmpty ? defaultBaseURL : stored
    }

    static var modelName: String {
        let stored = UserDefaults.standard.string(forKey: "reshelf.ollamaSelectedModel") ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    static func cacheKey(repositoryID: String,
                         commitSHA: String?,
                         modelName: String,
                         promptVersion: String = promptVersion) -> String {
        let raw = [
            repositoryID,
            commitSHA ?? "unknown-commit",
            modelName,
            promptVersion
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
