import Foundation

struct RecommendationGenerationResult: Equatable {
    var repositoryID: String
    var recommendations: [RepositoryRecommendationRecord]
    var ingestionJob: IngestionJobRecord
    var usedCache: Bool
}

enum RecommendationGenerationError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Recommendation generation was cancelled."
        }
    }
}

enum RecommendationEngine {
    static let supportedRecommendationTypes: Set<String> = [
        "related_repo",
        "alternative",
        "complementary_tool",
        "same_ecosystem",
        "same_workflow",
        "local_first_stack",
        "ai_tooling_stack",
        "mcp_compatible",
        "desktop_tooling",
        "pairs_well_with"
    ]

    static func generateRecommendations(repository: RepositoryRecord,
                                        database: IntelligenceDatabase = .shared,
                                        jobID: String? = nil) async throws -> RecommendationGenerationResult {
        try database.initialize()

        let cacheKey = try database.fetchRecommendationCacheKey(repositoryID: repository.id)
        if try database.hasRecommendations(repositoryID: repository.id, cacheKey: cacheKey) {
            let now = IntelligenceDatabase.iso8601String()
            let cachedJob = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                               repositoryID: repository.id,
                                               type: "recommendation_generation",
                                               status: "completed",
                                               priority: 0,
                                               progress: 1,
                                               error: nil,
                                               createdAt: now,
                                               startedAt: now,
                                               completedAt: now)
            try database.upsert(ingestionJob: cachedJob)
            await refreshEcosystemsIfPossible(database: database)
            RunbookAutoEnqueueService.maybeEnqueueAfterPipeline(repositoryID: repository.id, database: database)
            return RecommendationGenerationResult(repositoryID: repository.id,
                                                  recommendations: [],
                                                  ingestionJob: cachedJob,
                                                  usedCache: true)
        }

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                     repositoryID: repository.id,
                                     type: "recommendation_generation",
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
            let signals = try database.fetchGraphRecommendationSignals(repositoryID: repository.id)

            job.progress = 0.55
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)

            let completedAt = IntelligenceDatabase.iso8601String()
            let recommendations = try RepositoryRankingService.rank(repository: repository,
                                                                    signals: signals,
                                                                    database: database,
                                                                    cacheKey: cacheKey,
                                                                    generatedAt: completedAt)

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt
            try database.replaceRecommendations(repositoryID: repository.id,
                                                cacheKey: cacheKey,
                                                recommendations: recommendations,
                                                ingestionJob: job)
            await refreshEcosystemsIfPossible(database: database)
            RunbookAutoEnqueueService.maybeEnqueueAfterPipeline(repositoryID: repository.id, database: database)

            return RecommendationGenerationResult(repositoryID: repository.id,
                                                  recommendations: recommendations,
                                                  ingestionJob: job,
                                                  usedCache: false)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true || error is CancellationError {
                job.status = "cancelled"
                job.progress = 1
                job.error = "Cancelled by user."
                job.completedAt = IntelligenceDatabase.iso8601String()
                try? database.upsert(ingestionJob: job)
                throw RecommendationGenerationError.cancelled
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
            throw RecommendationGenerationError.cancelled
        }
    }

    private static func refreshEcosystemsIfPossible(database: IntelligenceDatabase) async {
        do {
            _ = try await EcosystemDiscoveryService.refresh(database: database)
        } catch {
            #if DEBUG
            print("[reshelf] Ecosystem discovery failed: \(error)")
            #endif
        }
    }
}
