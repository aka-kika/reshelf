import Foundation

struct GraphRelationshipResult: Equatable {
    var repositoryID: String
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var ingestionJob: IngestionJobRecord
}

enum GraphRelationshipError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Relationship generation was cancelled."
        }
    }
}

enum GraphRelationshipService {
    static func generateRelationships(repository: RepositoryRecord,
                                      database: IntelligenceDatabase = .shared,
                                      jobID: String? = nil) async throws -> GraphRelationshipResult {
        try database.initialize()

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                     repositoryID: repository.id,
                                     type: "relationship_generation",
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
            let manifests = try database.fetchRepositoryManifests(repositoryID: repository.id)
            let stackItems = try database.fetchDetectedStackItems(repositoryID: repository.id)
            let aiInsight = try database.fetchLatestAIInsight(repositoryID: repository.id)

            job.progress = 0.55
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)

            let completedAt = IntelligenceDatabase.iso8601String()
            let input = GraphInferenceInput(repository: repository,
                                            manifests: manifests,
                                            stackItems: stackItems,
                                            aiInsight: aiInsight)
            let inferred = RelationshipInferenceService.inferRelationships(input: input,
                                                                           createdAt: completedAt)

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt
            try database.upsertGraph(repositoryID: repository.id,
                                     nodes: inferred.nodes,
                                     edges: inferred.edges,
                                     ingestionJob: job)
            await generateRecommendationsIfPossible(repository: repository, database: database)

            return GraphRelationshipResult(repositoryID: repository.id,
                                           nodes: inferred.nodes,
                                           edges: inferred.edges,
                                           ingestionJob: job)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true || error is CancellationError {
                job.status = "cancelled"
                job.progress = 1
                job.error = "Cancelled by user."
                job.completedAt = IntelligenceDatabase.iso8601String()
                try? database.upsert(ingestionJob: job)
                throw GraphRelationshipError.cancelled
            }

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = IntelligenceDatabase.iso8601String()
            try? database.upsert(ingestionJob: job)
            throw error
        }
    }

    private static func throwIfCancelled(jobID: String, database: IntelligenceDatabase) throws {
        if try database.isIngestionJobCancelled(id: jobID) {
            throw GraphRelationshipError.cancelled
        }
    }

    private static func generateRecommendationsIfPossible(repository: RepositoryRecord,
                                                          database: IntelligenceDatabase) async {
        do {
            _ = try await RecommendationEngine.generateRecommendations(repository: repository, database: database)
        } catch {
            #if DEBUG
            print("[reshelf] Recommendation generation failed for \(repository.fullName): \(error)")
            #endif
        }
    }
}
