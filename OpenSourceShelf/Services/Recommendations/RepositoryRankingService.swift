import CryptoKit
import Foundation

enum RepositoryRankingService {
    static func rank(repository: RepositoryRecord,
                     signals: [GraphRecommendationSignal],
                     database: IntelligenceDatabase,
                     cacheKey: String,
                     generatedAt: String) throws -> [RepositoryRecommendationRecord] {
        let sourceStack = try database.fetchDetectedStackItems(repositoryID: repository.id)
        let sourceScore = try database.fetchLatestRepositoryScore(repositoryID: repository.id)
        let sourceCloneState = try database.fetchCloneState(repositoryID: repository.id)

        var bestByKey: [String: RecommendationCandidate] = [:]
        for signal in signals {
            let targetRepositoryID = targetRepositoryID(from: signal.targetKey)
            if targetRepositoryID == repository.id {
                continue
            }

            let targetStack: [DetectedStackItemRecord]
            let targetScore: RepositoryScoreRecord?
            let targetCloneState: CloneStateRecord?
            if let targetRepositoryID {
                targetStack = try database.fetchDetectedStackItems(repositoryID: targetRepositoryID)
                targetScore = try database.fetchLatestRepositoryScore(repositoryID: targetRepositoryID)
                targetCloneState = try database.fetchCloneState(repositoryID: targetRepositoryID)
            } else {
                targetStack = []
                targetScore = nil
                targetCloneState = nil
            }

            let context = RecommendationScoringContext(sourceStackItems: sourceStack,
                                                       sourceScore: sourceScore,
                                                       sourceCloneState: sourceCloneState,
                                                       targetStackItems: targetStack,
                                                       targetScore: targetScore,
                                                       targetCloneState: targetCloneState)
            guard let candidate = RelationshipScoringService.score(signal: signal, context: context),
                  candidate.score >= minimumScore(for: candidate.recommendationType) else {
                continue
            }

            let key = "\(candidate.recommendationType)|\(signal.targetNodeID)"
            if let existing = bestByKey[key], existing.score >= candidate.score {
                continue
            }
            bestByKey[key] = candidate
        }

        return bestByKey.values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.signal.targetLabel < rhs.signal.targetLabel
                }
                return lhs.score > rhs.score
            }
            .prefix(24)
            .map { candidate in
                RepositoryRecommendationRecord(
                    id: stableID(parts: [repository.id, candidate.signal.targetNodeID, candidate.recommendationType]),
                    sourceRepositoryID: repository.id,
                    targetNodeID: candidate.signal.targetNodeID,
                    targetRepositoryID: candidate.targetRepositoryID,
                    recommendationType: candidate.recommendationType,
                    score: candidate.score,
                    explanation: candidate.explanation,
                    signalsJSON: encodeSignals(candidate.signals),
                    cacheKey: cacheKey,
                    generatedAt: generatedAt
                )
            }
    }

    static func clusterLabel(for recommendation: RepositoryRecommendationSummary) -> String {
        let text = [
            recommendation.recommendationType,
            recommendation.targetLabel,
            recommendation.explanation,
            recommendation.signalsJSON
        ].joined(separator: " ").lowercased()

        if text.contains("mcp") {
            return "MCP ecosystem"
        }
        if text.contains("ollama") || text.contains("local ai") || text.contains("ai_tooling") {
            return "Local AI ecosystem"
        }
        if text.contains("agent") {
            return "Agent tooling"
        }
        if text.contains("electron") || text.contains("tauri") || text.contains("desktop") || text.contains("macos") {
            return "Desktop tooling"
        }
        if text.contains("postgres") || text.contains("sqlite") || text.contains("database") || text.contains("supabase") {
            return "Database tooling"
        }
        if text.contains("workflow") || text.contains("automation") {
            return "Workflow automation"
        }
        return "Same ecosystem"
    }

    private static func minimumScore(for recommendationType: String) -> Double {
        switch recommendationType {
        case "related_repo":
            return 55
        case "alternative":
            return 50
        default:
            return 45
        }
    }

    private static func targetRepositoryID(from key: String) -> String? {
        guard key.hasPrefix("repository:") else {
            return nil
        }
        let id = String(key.dropFirst("repository:".count))
        return id.hasPrefix("external:") ? nil : id
    }

    private static func encodeSignals(_ signals: [String]) -> String {
        guard let data = try? JSONEncoder().encode(signals),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func stableID(parts: [String]) -> String {
        let raw = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "recommendation-\(digest.map { String(format: "%02x", $0) }.joined())"
    }
}
