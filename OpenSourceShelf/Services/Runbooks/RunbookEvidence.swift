import CryptoKit
import Foundation

struct RunbookCommand: Equatable {
    var command: String
    var source: String
    var confidence: String
}

struct RunbookCommandSet: Equatable {
    var installCommands: [RunbookCommand] = []
    var runCommands: [RunbookCommand] = []
    var dockerCommands: [RunbookCommand] = []
    var environmentNotes: [String] = []
}

struct RunbookEvidence: Equatable {
    var repository: RepositoryRecord
    var metadata: RepositoryMetadataRecord?
    var clonePath: String?
    var readmeExcerpt: String?
    var manifests: [RepositoryManifestRecord]
    var stackItems: [DetectedStackItemRecord]
    var aiInsight: AIInsightRecord?
    var repositoryScore: RepositoryScoreRecord?
    var envFileExamples: [String]
    var commands: RunbookCommandSet
}

enum RunbookCache {
    static let promptVersion = "stage18-v1"

    static var modelName: String { AIAnalysisCache.modelName }
    static var baseURL: String { AIAnalysisCache.baseURL }

    static func evidenceSignature(repositoryID: String,
                                  commitSHA: String?,
                                  readmeHash: String?,
                                  manifestStamp: String?,
                                  stackStamp: String?,
                                  aiStamp: String?,
                                  promptVersion: String = promptVersion,
                                  modelName: String = modelName) -> String {
        let raw = [
            repositoryID,
            commitSHA ?? "unknown-commit",
            readmeHash ?? "no-readme",
            manifestStamp ?? "no-manifests",
            stackStamp ?? "no-stack",
            aiStamp ?? "no-ai",
            promptVersion,
            modelName
        ].joined(separator: "|")
        return sha256(raw)
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
