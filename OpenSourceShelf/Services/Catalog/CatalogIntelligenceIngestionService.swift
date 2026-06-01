import Foundation

enum CatalogIntelligenceIngestionService {
    static func fetchIntelligence(for toolProject: ToolProject,
                                  database: IntelligenceDatabase = .shared) async -> CatalogIntelligenceFetchOutcome {
        guard let githubURL = IntelligenceRepositoryBridge.resolvedGitHubURL(for: toolProject) else {
            let trimmed = toolProject.githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty,
               !toolProject.name.trimmingCharacters(in: .whitespacesAndNewlines).contains("/") {
                return .skippedNoGitHubURL
            }
            return .skippedInvalidURL
        }

        let snapshot = CatalogIntelligenceStatusResolver.snapshot(for: toolProject, database: database)
        switch snapshot.status {
        case .ready:
            return .skippedAlreadyReady
        case .queued, .fetching, .cloning, .analyzing:
            return .skippedInProgress
        case .notFetched, .failed:
            break
        }

        if let repositoryID = snapshot.repositoryID ?? IntelligenceRepositoryBridge.repositoryID(for: toolProject,
                                                                                                database: database) {
            if let active = try? database.fetchActivePipelineJobs(repositoryID: repositoryID), !active.isEmpty {
                return .skippedInProgress
            }
            if CatalogIntelligenceStatusResolver.isReady(repositoryID: repositoryID, database: database) {
                return .skippedAlreadyReady
            }
        }

        do {
            try database.initialize()
            _ = try IntelligenceRepositoryBridge.createIntelligenceRepositoryIfNeeded(for: toolProject,
                                                                                      database: database)
            _ = try await RepositoryIngestionService.ingestMetadata(githubURL: githubURL, database: database)
            if let repositoryID = IntelligenceRepositoryBridge.repositoryID(for: toolProject, database: database) {
                AppRefreshBus.emit(.intelligenceUpdated(repositoryID: repositoryID))
            }
            AppRefreshBus.emit(.queueUpdated)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func cloneLocally(for toolProject: ToolProject,
                             database: IntelligenceDatabase = .shared) async -> CatalogCloneLocallyOutcome {
        guard IntelligenceRepositoryBridge.resolvedGitHubURL(for: toolProject) != nil else {
            return .failed("Add a valid GitHub URL before cloning.")
        }

        do {
            try database.initialize()
            _ = try IntelligenceRepositoryBridge.createIntelligenceRepositoryIfNeeded(for: toolProject,
                                                                                      database: database)
            guard let repository = IntelligenceRepositoryBridge.findIntelligenceRepository(for: toolProject,
                                                                                             database: database) else {
                return .failed("No intelligence record for this project yet. Refresh from GitHub first.")
            }
            _ = try await RepositoryCloneService.cloneOrFetch(repository: repository, database: database)
            AppRefreshBus.emit(.intelligenceUpdated(repositoryID: repository.id))
            AppRefreshBus.emit(.queueUpdated)
            AppRefreshBus.emit(.catalogStateUpdated)
            return .succeeded
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func fetchIntelligence(for toolProjects: [ToolProject],
                                  database: IntelligenceDatabase = .shared) async -> CatalogIntelligenceBatchResult {
        var started = 0
        var skippedReady = 0
        var skippedInProgress = 0
        var skippedInvalid = 0
        var failed = 0

        for project in toolProjects {
            let outcome = await fetchIntelligence(for: project, database: database)
            switch outcome {
            case .started:
                started += 1
            case .skippedAlreadyReady:
                skippedReady += 1
            case .skippedInProgress:
                skippedInProgress += 1
            case .skippedInvalidURL, .skippedNoGitHubURL:
                skippedInvalid += 1
            case .failed:
                failed += 1
            }
            await Task.yield()
        }

        return CatalogIntelligenceBatchResult(started: started,
                                              skippedReady: skippedReady,
                                              skippedInProgress: skippedInProgress,
                                              skippedInvalid: skippedInvalid,
                                              failed: failed)
    }
}
