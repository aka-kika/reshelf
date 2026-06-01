import Foundation

struct RepositoryRunbookResult: Equatable {
    let runbook: RepositoryRunbookRecord
    let ingestionJob: IngestionJobRecord
    let usedCache: Bool
}

enum RepositoryRunbookError: LocalizedError {
    case repositoryNotFound
    case cancelled
    case insufficientEvidence

    var errorDescription: String? {
        switch self {
        case .repositoryNotFound:
            return "Repository was not found in the intelligence database."
        case .cancelled:
            return "Runbook generation was cancelled."
        case .insufficientEvidence:
            return "Not enough evidence to generate a runbook. Fetch intelligence and clone the repository first."
        }
    }
}

enum RepositoryRunbookService {
    static func fetchLatest(repositoryID: String,
                            database: IntelligenceDatabase = .shared) throws -> RepositoryRunbookRecord? {
        try database.fetchLatestRunbook(repositoryID: repositoryID)
    }

    static func isStale(_ runbook: RepositoryRunbookRecord,
                       repositoryID: String,
                       database: IntelligenceDatabase = .shared) throws -> Bool {
        try evaluateFreshness(runbook, repositoryID: repositoryID, database: database).isStale
    }

    static func evaluateFreshness(_ runbook: RepositoryRunbookRecord?,
                                  repositoryID: String,
                                  database: IntelligenceDatabase = .shared) throws -> RunbookFreshnessState {
        guard let repository = try database.fetchRepository(id: repositoryID) else {
            return runbook == nil ? .neverGenerated : .stale(changes: [RunbookEvidenceChange(message: "Repository record missing.")])
        }
        let evidence = try RunbookEvidenceCollector.collect(repository: repository, database: database)
        return RunbookFreshnessEvaluator.evaluate(runbook: runbook, evidence: evidence)
    }

    static func enqueueGeneration(repositoryID: String,
                                  force: Bool = false,
                                  database: IntelligenceDatabase = .shared) throws -> String {
        try RunbookGenerationCoordinator.enqueue(repositoryID: repositoryID, force: force, database: database)
    }

    static func recordExport(runbookID: String,
                             database: IntelligenceDatabase = .shared) throws {
        let exportedAt = IntelligenceDatabase.iso8601String()
        try database.updateRunbookLastExportedAt(runbookID: runbookID, exportedAt: exportedAt)
    }

    static func generate(repositoryID: String,
                         force: Bool = false,
                         database: IntelligenceDatabase = .shared,
                         fileManager: FileManager = .default,
                         jobID: String? = nil) async throws -> RepositoryRunbookResult {
        try database.initialize()

        guard let repository = try database.fetchRepository(id: repositoryID) else {
            throw RepositoryRunbookError.repositoryNotFound
        }

        let evidence = try RunbookEvidenceCollector.collect(repository: repository,
                                                            database: database,
                                                            fileManager: fileManager)
        let signature = RunbookEvidenceCollector.computeEvidenceSignature(for: evidence)

        if !force, let cached = try database.fetchRunbook(evidenceSignature: signature) {
            let cachedJob = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                               repositoryID: repositoryID,
                                               type: "generate_runbook",
                                               status: "completed",
                                               priority: 0,
                                               progress: 1,
                                               error: "Used cached runbook.",
                                               createdAt: IntelligenceDatabase.iso8601String(),
                                               startedAt: IntelligenceDatabase.iso8601String(),
                                               completedAt: IntelligenceDatabase.iso8601String())
            try database.upsert(ingestionJob: cachedJob)
            return RepositoryRunbookResult(runbook: cached, ingestionJob: cachedJob, usedCache: true)
        }

        guard evidence.clonePath != nil || evidence.readmeExcerpt != nil || !evidence.manifests.isEmpty else {
            throw RepositoryRunbookError.insufficientEvidence
        }

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                     repositoryID: repositoryID,
                                     type: "generate_runbook",
                                     status: "running",
                                     priority: 0,
                                     progress: 0.15,
                                     error: nil,
                                     createdAt: now,
                                     startedAt: now,
                                     completedAt: nil)
        if let existingJob = jobID.flatMap({ try? database.fetchIngestionJob(id: $0) }) {
            job.createdAt = existingJob.createdAt
            job.startedAt = now
        }
        try database.upsert(ingestionJob: job)
        try throwIfCancelled(jobID: job.id, database: database)

        do {
            let deterministic = RunbookGenerator.buildDeterministicMarkdown(from: evidence)
            job.progress = 0.45
            try database.upsert(ingestionJob: job)

            let markdown: String
            let generatedBy: String
            let modelName: String?
            let promptVersion = RunbookCache.promptVersion

            if AISettingsSnapshot.isConfigured(AISettingsSnapshot.resolvedProvider()) {
                let prompt = RunbookGenerator.buildAIPrompt(from: evidence, deterministicDraft: deterministic)
                job.progress = 0.65
                try database.upsert(ingestionJob: job)
                try throwIfCancelled(jobID: job.id, database: database)

                let aiResult = await AICompletionService.generateFromStoredPreferences(prompt: prompt)
                let aiOutput = aiResult.text
                if let provider = aiResult.provider,
                   !aiOutput.isEmpty,
                   !aiOutput.hasPrefix("⚠️"),
                   aiOutput != "Invalid URL",
                   !aiOutput.hasPrefix("Error") {
                    markdown = sanitizeAIMarkdown(aiOutput, fallback: deterministic)
                    generatedBy = provider.rawValue
                    modelName = AISettingsSnapshot.model(for: provider)
                } else {
                    markdown = deterministic
                    generatedBy = "deterministic"
                    modelName = nil
                }
            } else {
                markdown = deterministic
                generatedBy = "deterministic"
                modelName = nil
            }

            let completedAt = IntelligenceDatabase.iso8601String()
            let summary = evidence.aiInsight?.summary ?? evidence.metadata?.description
            let components = RunbookEvidenceComponents.from(evidence: evidence)
            let runbook = RepositoryRunbookRecord(id: UUID().uuidString,
                                                  repositoryID: repositoryID,
                                                  title: "Local Test Runbook — \(repository.fullName)",
                                                  summary: summary,
                                                  markdown: markdown,
                                                  evidenceSignature: signature,
                                                  generatedBy: generatedBy,
                                                  modelName: modelName,
                                                  promptVersion: promptVersion,
                                                  evidenceComponentsJSON: components.encodedJSON(),
                                                  lastExportedAt: nil,
                                                  createdAt: now,
                                                  updatedAt: completedAt)

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt
            try database.upsert(runbook: runbook, ingestionJob: job)

            return RepositoryRunbookResult(runbook: runbook, ingestionJob: job, usedCache: false)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true || error is CancellationError {
                job.status = "cancelled"
                job.progress = 1
                job.error = "Cancelled by user."
                job.completedAt = IntelligenceDatabase.iso8601String()
                try? database.upsert(ingestionJob: job)
                throw RepositoryRunbookError.cancelled
            }

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = IntelligenceDatabase.iso8601String()
            try? database.upsert(ingestionJob: job)
            throw error
        }
    }

    private static func sanitizeAIMarkdown(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("# Local Test Runbook") || trimmed.contains("## Repository") else {
            return fallback
        }
        if !trimmed.contains("not been executed") {
            return RunbookGenerator.disclaimer + "\n\n" + trimmed
        }
        return trimmed
    }

    private static func throwIfCancelled(jobID: String, database: IntelligenceDatabase) throws {
        if try database.isIngestionJobCancelled(id: jobID) {
            throw RepositoryRunbookError.cancelled
        }
    }
}
