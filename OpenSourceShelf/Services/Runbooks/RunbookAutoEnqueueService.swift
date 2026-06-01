import Foundation

enum RunbookAutoEnqueueSettings {
    static let userDefaultsKey = "reshelf.autoGenerateRunbookAfterIntelligence"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func syncFromSettings(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}

enum RunbookAutoEnqueueService {
    static func maybeEnqueueAfterPipeline(repositoryID: String,
                                          database: IntelligenceDatabase = .shared) {
        guard RunbookAutoEnqueueSettings.isEnabled else { return }
        Task {
            try? await enqueueIfNeeded(repositoryID: repositoryID, database: database)
        }
    }

    static func enqueueIfNeeded(repositoryID: String,
                              database: IntelligenceDatabase = .shared) async throws {
        try database.initialize()

        if RunbookGenerationCoordinator.isGenerating(repositoryID: repositoryID, database: database) {
            return
        }

        if let active = try database.fetchActiveIngestionJob(repositoryID: repositoryID, type: "generate_runbook") {
            guard active.status == "pending" || active.status == "running" else { return }
            return
        }

        if let runbook = try database.fetchLatestRunbook(repositoryID: repositoryID) {
            let freshness = try RepositoryRunbookService.evaluateFreshness(runbook,
                                                                           repositoryID: repositoryID,
                                                                           database: database)
            if case .fresh = freshness {
                return
            }
        }

        _ = try RunbookGenerationCoordinator.enqueue(repositoryID: repositoryID, force: false, database: database)
    }
}
