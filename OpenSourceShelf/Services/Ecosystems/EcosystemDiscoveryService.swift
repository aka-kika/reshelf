import Foundation
import GRDB

struct EcosystemDiscoveryResult: Equatable {
    var clusters: [EcosystemClusterRecord]
    var ingestionJob: IngestionJobRecord
    var usedCache: Bool
}

enum EcosystemDiscoveryError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Ecosystem discovery was cancelled."
        }
    }
}

enum EcosystemDiscoveryService {
    static func refresh(database: IntelligenceDatabase = .shared,
                        jobID: String? = nil) async throws -> EcosystemDiscoveryResult {
        try database.initialize()
        let cacheKey = try database.fetchEcosystemCacheKey()

        if try database.hasEcosystemClusters(cacheKey: cacheKey) {
            let now = IntelligenceDatabase.iso8601String()
            let job = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                         repositoryID: nil,
                                         type: "ecosystem_discovery",
                                         status: "completed",
                                         priority: 0,
                                         progress: 1,
                                         error: nil,
                                         createdAt: now,
                                         startedAt: now,
                                         completedAt: now)
            try database.upsert(ingestionJob: job)
            return EcosystemDiscoveryResult(clusters: [], ingestionJob: job, usedCache: true)
        }

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                     repositoryID: nil,
                                     type: "ecosystem_discovery",
                                     status: "running",
                                     priority: 0,
                                     progress: 0.2,
                                     error: nil,
                                     createdAt: now,
                                     startedAt: now,
                                     completedAt: nil)
        try database.upsert(ingestionJob: job)

        do {
            try throwIfCancelled(jobID: job.id, database: database)
            let input = try collectInput(database: database)

            job.progress = 0.6
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)

            let completedAt = IntelligenceDatabase.iso8601String()
            let clusters = WorkflowClusterService.makeClusters(input: input,
                                                               cacheKey: cacheKey,
                                                               generatedAt: completedAt)

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt
            try database.replaceEcosystemClusters(cacheKey: cacheKey,
                                                  clusters: clusters,
                                                  ingestionJob: job)

            return EcosystemDiscoveryResult(clusters: clusters, ingestionJob: job, usedCache: false)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true || error is CancellationError {
                job.status = "cancelled"
                job.progress = 1
                job.error = "Cancelled by user."
                job.completedAt = IntelligenceDatabase.iso8601String()
                try? database.upsert(ingestionJob: job)
                throw EcosystemDiscoveryError.cancelled
            }

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = IntelligenceDatabase.iso8601String()
            try? database.upsert(ingestionJob: job)
            throw error
        }
    }

    private static func collectInput(database: IntelligenceDatabase) throws -> EcosystemDiscoveryInput {
        try database.read { db in
            let repositories = try Row.fetchAll(
                db,
                sql: "SELECT id, full_name, name FROM repositories ORDER BY full_name"
            ).map {
                EcosystemRepositoryFact(id: $0["id"], fullName: $0["full_name"], name: $0["name"])
            }

            let stackItems = try Row.fetchAll(
                db,
                sql: """
                SELECT repository_id, name, category, confidence
                FROM detected_stack_items
                ORDER BY repository_id, confidence DESC, name
                """
            ).map {
                EcosystemStackFact(repositoryID: $0["repository_id"],
                                   name: $0["name"],
                                   category: $0["category"],
                                   confidence: $0["confidence"])
            }

            let relationships = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    REPLACE(source.key, 'repository:', '') AS source_repository_id,
                    e.relationship_type,
                    target.label AS target_label,
                    target.type AS target_type,
                    e.confidence
                FROM graph_edges e
                JOIN graph_nodes source ON source.id = e.source_node_id
                JOIN graph_nodes target ON target.id = e.target_node_id
                WHERE source.type = 'repository'
                  AND source.key LIKE 'repository:%'
                ORDER BY e.confidence DESC, target.label
                """
            ).map {
                EcosystemRelationshipFact(sourceRepositoryID: $0["source_repository_id"],
                                          relationshipType: $0["relationship_type"],
                                          targetLabel: $0["target_label"],
                                          targetType: $0["target_type"],
                                          confidence: $0["confidence"])
            }

            let recommendations = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    r.source_repository_id,
                    r.recommendation_type,
                    target.label AS target_label,
                    r.score,
                    r.explanation
                FROM repository_recommendations r
                JOIN graph_nodes target ON target.id = r.target_node_id
                ORDER BY r.score DESC, target.label
                """
            ).map {
                EcosystemRecommendationFact(sourceRepositoryID: $0["source_repository_id"],
                                            recommendationType: $0["recommendation_type"],
                                            targetLabel: $0["target_label"],
                                            score: $0["score"],
                                            explanation: $0["explanation"])
            }

            let scoreRows = try Row.fetchAll(
                db,
                sql: """
                SELECT rs.*
                FROM repository_scores rs
                JOIN (
                    SELECT repository_id, MAX(generated_at) AS generated_at
                    FROM repository_scores
                    GROUP BY repository_id
                ) latest ON latest.repository_id = rs.repository_id
                        AND latest.generated_at = rs.generated_at
                """
            )
            var scores: [String: RepositoryScoreRecord] = [:]
            for row in scoreRows {
                let score = RepositoryScoreRecord(
                    id: row["id"],
                    repositoryID: row["repository_id"],
                    cacheKey: row["cache_key"],
                    setupComplexity: row["setup_complexity"],
                    localFirstScore: row["local_first_score"],
                    experimentationPriority: row["experimentation_priority"],
                    ecosystemInfluence: row["ecosystem_influence"],
                    personalRelevance: row["personal_relevance"],
                    generatedAt: row["generated_at"]
                )
                scores[score.repositoryID] = score
            }

            let insightRows = try Row.fetchAll(
                db,
                sql: """
                SELECT repository_id, classifications_json
                FROM ai_insights
                ORDER BY repository_id, generated_at DESC
                """
            )
            var classificationsByRepositoryID: [String: [String]] = [:]
            for row in insightRows {
                let repositoryID: String = row["repository_id"]
                if classificationsByRepositoryID[repositoryID] != nil {
                    continue
                }
                let json: String = row["classifications_json"]
                classificationsByRepositoryID[repositoryID] = decodeStringArray(json)
            }

            return EcosystemDiscoveryInput(repositories: repositories,
                                           stackItems: stackItems,
                                           relationships: relationships,
                                           recommendations: recommendations,
                                           scores: scores,
                                           classificationsByRepositoryID: classificationsByRepositoryID)
        }
    }

    private static func throwIfCancelled(jobID: String, database: IntelligenceDatabase) throws {
        if try database.isIngestionJobCancelled(id: jobID) {
            throw EcosystemDiscoveryError.cancelled
        }
    }

    private static func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}
