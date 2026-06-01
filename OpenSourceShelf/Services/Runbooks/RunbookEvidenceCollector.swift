import CryptoKit
import Foundation

enum RunbookEvidenceCollector {
    static func collect(repository: RepositoryRecord,
                        database: IntelligenceDatabase = .shared,
                        fileManager: FileManager = .default) throws -> RunbookEvidence {
        try database.initialize()

        let metadata = try database.fetchMetadata(repositoryID: repository.id)
        let manifests = try database.fetchRepositoryManifests(repositoryID: repository.id)
        let stackItems = try database.fetchDetectedStackItems(repositoryID: repository.id)
        let aiInsight = try database.fetchLatestAIInsight(repositoryID: repository.id)
        let repositoryScore = aiInsight.flatMap { try? database.fetchRepositoryScore(cacheKey: $0.cacheKey) }
        let readmeExcerpt = readmeExcerpt(repository: repository, fileManager: fileManager)
        let envExamples = envFileExamples(repository: repository, fileManager: fileManager)

        var evidence = RunbookEvidence(repository: repository,
                                       metadata: metadata,
                                       clonePath: repository.localPath,
                                       readmeExcerpt: readmeExcerpt,
                                       manifests: manifests,
                                       stackItems: stackItems,
                                       aiInsight: aiInsight,
                                       repositoryScore: repositoryScore,
                                       envFileExamples: envExamples,
                                       commands: RunbookCommandSet())
        evidence.commands = RunbookCommandExtractor.extract(from: evidence, fileManager: fileManager)
        return evidence
    }

    static func readmeHash(from excerpt: String?) -> String? {
        guard let excerpt, !excerpt.isEmpty else { return nil }
        return RunbookEvidenceCollector.sha256(excerpt)
    }

    static func manifestStamp(from manifests: [RepositoryManifestRecord]) -> String? {
        guard !manifests.isEmpty else { return nil }
        let parts = manifests.map { "\($0.path)|\($0.type)|\($0.detectedAt)" }.sorted()
        return sha256(parts.joined(separator: ";"))
    }

    static func stackStamp(from stackItems: [DetectedStackItemRecord]) -> String? {
        guard !stackItems.isEmpty else { return nil }
        let parts = stackItems.map { "\($0.category)|\($0.name)|\($0.detectedAt)" }.sorted()
        return sha256(parts.joined(separator: ";"))
    }

    static func aiStamp(from insight: AIInsightRecord?) -> String? {
        guard let insight else { return nil }
        return "\(insight.cacheKey)|\(insight.generatedAt)"
    }

    static func computeEvidenceSignature(for evidence: RunbookEvidence,
                                         promptVersion: String = RunbookCache.promptVersion,
                                         modelName: String = RunbookCache.modelName) -> String {
        RunbookCache.evidenceSignature(repositoryID: evidence.repository.id,
                                       commitSHA: evidence.repository.latestCommitSHA,
                                       readmeHash: readmeHash(from: evidence.readmeExcerpt),
                                       manifestStamp: manifestStamp(from: evidence.manifests),
                                       stackStamp: stackStamp(from: evidence.stackItems),
                                       aiStamp: aiStamp(from: evidence.aiInsight),
                                       promptVersion: promptVersion,
                                       modelName: modelName)
    }

    private static func readmeExcerpt(repository: RepositoryRecord, fileManager: FileManager) -> String? {
        guard let localPath = repository.localPath else { return nil }
        let rootURL = URL(fileURLWithPath: localPath, isDirectory: true)
        let candidates = ["README.md", "Readme.md", "readme.md", "README", "README.markdown", "README.rst"]
        for candidate in candidates {
            let url = rootURL.appendingPathComponent(candidate)
            guard fileManager.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            return String(text.prefix(5_000))
        }
        return nil
    }

    private static func envFileExamples(repository: RepositoryRecord, fileManager: FileManager) -> [String] {
        guard let localPath = repository.localPath else { return [] }
        let rootURL = URL(fileURLWithPath: localPath, isDirectory: true)
        let names = [".env.example", ".env.sample", "env.example", ".env.template"]
        var results: [String] = []
        for name in names {
            let url = rootURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            results.append(String(text.prefix(800)))
        }
        return results
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
