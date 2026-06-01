import Foundation

extension Notification.Name {
    static let runbookGenerationDidComplete = Notification.Name("runbookGenerationDidComplete")
}

enum RunbookGenerationCoordinator {
    private static var activeRepositoryIDs: Set<String> = []
    private static let lock = NSLock()

    @discardableResult
    static func enqueue(repositoryID: String,
                        force: Bool,
                        database: IntelligenceDatabase = .shared) throws -> String {
        try database.initialize()

        lock.lock()
        let alreadyRunning = activeRepositoryIDs.contains(repositoryID)
        if !alreadyRunning {
            activeRepositoryIDs.insert(repositoryID)
        }
        lock.unlock()

        if alreadyRunning {
            if let existing = try database.fetchActiveIngestionJob(repositoryID: repositoryID, type: "generate_runbook") {
                return existing.id
            }
        }

        let jobID = UUID().uuidString
        let now = IntelligenceDatabase.iso8601String()
        let job = IngestionJobRecord(id: jobID,
                                     repositoryID: repositoryID,
                                     type: "generate_runbook",
                                     status: "pending",
                                     priority: 0,
                                     progress: 0,
                                     error: nil,
                                     createdAt: now,
                                     startedAt: nil,
                                     completedAt: nil)
        try database.upsert(ingestionJob: job)

        Task {
            defer {
                lock.lock()
                activeRepositoryIDs.remove(repositoryID)
                lock.unlock()
            }
            do {
                _ = try await RepositoryRunbookService.generate(repositoryID: repositoryID,
                                                                force: force,
                                                                database: database,
                                                                jobID: jobID)
            } catch {
                // Job record updated by service.
            }
            await MainActor.run {
                AppRefreshBus.emit(.runbookGenerated(repositoryID: repositoryID))
            }
        }

        return jobID
    }

    static func isGenerating(repositoryID: String, database: IntelligenceDatabase = .shared) -> Bool {
        lock.lock()
        let active = activeRepositoryIDs.contains(repositoryID)
        lock.unlock()
        if active { return true }
        guard let job = try? database.fetchActiveIngestionJob(repositoryID: repositoryID, type: "generate_runbook") else {
            return false
        }
        return job.status == "pending" || job.status == "running"
    }
}
