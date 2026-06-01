import Foundation

enum CatalogIntelligenceStateService {
    static func buildStates(for projects: [ToolProject],
                            database: IntelligenceDatabase = .shared,
                            includeFreshnessEvaluation: Bool = true) -> [UUID: CatalogIntelligenceState] {
        do {
            try database.initialize()
        } catch {
            return Dictionary(uniqueKeysWithValues: projects.map {
                ($0.id, fallbackState(for: $0, errorMessage: error.localizedDescription))
            })
        }

        var repositoryByProjectID: [UUID: RepositoryRecord] = [:]
        for project in projects {
            if let repository = IntelligenceRepositoryBridge.findIntelligenceRepository(for: project, database: database) {
                repositoryByProjectID[project.id] = repository
            }
        }

        let repositoryIDs = Array(Set(repositoryByProjectID.values.map(\.id)))
        let runbooks = (try? database.fetchLatestRunbooks(repositoryIDs: repositoryIDs)) ?? [:]
        let cloneStates = (try? database.fetchCloneStates(repositoryIDs: repositoryIDs)) ?? [:]
        let activeRunbookJobs = (try? database.fetchActiveRunbookJobs(repositoryIDs: repositoryIDs)) ?? [:]

        var result: [UUID: CatalogIntelligenceState] = [:]
        for project in projects {
            if let repository = repositoryByProjectID[project.id] {
                let snapshot = CatalogIntelligenceStatusResolver.snapshot(for: project, database: database)
                let runbook = runbooks[repository.id]
                let activeJob = activeRunbookJobs[repository.id]
                let freshness: RunbookFreshnessState?
                let badge: CatalogRunbookBadge
                if includeFreshnessEvaluation {
                    freshness = catalogFreshness(runbook: runbook, repository: repository, database: database)
                    badge = runbookBadge(hasIntelligence: true,
                                         activeJob: activeJob,
                                         runbook: runbook,
                                         freshness: freshness)
                } else {
                    freshness = nil
                    badge = lightweightRunbookBadge(activeJob: activeJob, runbook: runbook)
                }

                result[project.id] = CatalogIntelligenceState(
                    projectID: project.id,
                    repositoryID: repository.id,
                    hasIntelligence: true,
                    cloneStatus: cloneStates[repository.id]?.status,
                    analysisStatus: snapshot.status,
                    runbookBadge: badge,
                    runbookFreshness: freshness,
                    runbookLastGeneratedAt: runbook?.updatedAt,
                    runbookLastExportedAt: runbook?.lastExportedAt,
                    activeJobStatus: activeJob?.status,
                    staleReason: freshness?.summaryText,
                    analysisErrorMessage: snapshot.errorMessage
                )
            } else {
                let hasGitHubIdentity = IntelligenceRepositoryBridge.resolvedGitHubURL(for: project) != nil
                let snapshot = CatalogIntelligenceStatusResolver.snapshot(for: project, database: database)
                result[project.id] = CatalogIntelligenceState(
                    projectID: project.id,
                    repositoryID: snapshot.repositoryID,
                    hasIntelligence: false,
                    cloneStatus: nil,
                    analysisStatus: hasGitHubIdentity ? snapshot.status : .notFetched,
                    runbookBadge: .noIntelligence,
                    runbookFreshness: nil,
                    runbookLastGeneratedAt: nil,
                    runbookLastExportedAt: nil,
                    activeJobStatus: nil,
                    staleReason: nil,
                    analysisErrorMessage: snapshot.errorMessage
                )
            }
        }

        return result
    }

    /// Fast badge for catalog list polling — skips evidence signature work.
    private static func lightweightRunbookBadge(activeJob: IngestionJobRecord?,
                                                runbook: RepositoryRunbookRecord?) -> CatalogRunbookBadge {
        if activeJob != nil { return .generating }
        guard let runbook else { return .neverGenerated }
        if runbook.promptVersion != RunbookCache.promptVersion { return .staleRunbook }
        return .freshRunbook
    }

    private static func runbookBadge(hasIntelligence: Bool,
                                     activeJob: IngestionJobRecord?,
                                     runbook: RepositoryRunbookRecord?,
                                     freshness: RunbookFreshnessState?) -> CatalogRunbookBadge {
        guard hasIntelligence else { return .noIntelligence }
        if activeJob != nil { return .generating }
        guard runbook != nil else { return .neverGenerated }
        switch freshness {
        case .some(.fresh):
            return .freshRunbook
        case .some(.neverGenerated):
            return .neverGenerated
        case .some(.stale), .some(.generatedWithOlderTemplate):
            return .staleRunbook
        case .none:
            return .neverGenerated
        }
    }

    /// DB-backed freshness check for catalog rows — avoids reading clone files on every refresh.
    private static func catalogFreshness(runbook: RepositoryRunbookRecord?,
                                         repository: RepositoryRecord,
                                         database: IntelligenceDatabase) -> RunbookFreshnessState? {
        guard let runbook else { return .neverGenerated }

        do {
            let metadata = try database.fetchMetadata(repositoryID: repository.id)
            let manifests = try database.fetchRepositoryManifests(repositoryID: repository.id)
            let stackItems = try database.fetchDetectedStackItems(repositoryID: repository.id)
            let aiInsight = try database.fetchLatestAIInsight(repositoryID: repository.id)
            let repositoryScore = aiInsight.flatMap { try? database.fetchRepositoryScore(cacheKey: $0.cacheKey) }

            var evidence = RunbookEvidence(repository: repository,
                                           metadata: metadata,
                                           clonePath: repository.localPath,
                                           readmeExcerpt: nil,
                                           manifests: manifests,
                                           stackItems: stackItems,
                                           aiInsight: aiInsight,
                                           repositoryScore: repositoryScore,
                                           envFileExamples: [],
                                           commands: RunbookCommandSet())
            let currentSignature = RunbookEvidenceCollector.computeEvidenceSignature(for: evidence)
            if runbook.evidenceSignature == currentSignature {
                if runbook.promptVersion != RunbookCache.promptVersion {
                    return .generatedWithOlderTemplate(changes: [
                        RunbookEvidenceChange(message: "Runbook template changed since last generation.")
                    ])
                }
                return .fresh
            }

            evidence.readmeExcerpt = nil
            return RunbookFreshnessEvaluator.evaluate(runbook: runbook, evidence: evidence)
        } catch {
            return runbook.promptVersion == RunbookCache.promptVersion ? .stale(changes: [
                RunbookEvidenceChange(message: "Evidence changed since last generation.")
            ]) : .generatedWithOlderTemplate(changes: [
                RunbookEvidenceChange(message: "Runbook template or evidence changed.")
            ])
        }
    }

    private static func fallbackState(for project: ToolProject, errorMessage: String) -> CatalogIntelligenceState {
        CatalogIntelligenceState(
            projectID: project.id,
            repositoryID: nil,
            hasIntelligence: false,
            cloneStatus: nil,
            analysisStatus: .failed,
            runbookBadge: .noIntelligence,
            runbookFreshness: nil,
            runbookLastGeneratedAt: nil,
            runbookLastExportedAt: nil,
            activeJobStatus: nil,
            staleReason: nil,
            analysisErrorMessage: errorMessage
        )
    }
}

@MainActor
final class CatalogIntelligenceStateStore: ObservableObject {
    @Published private(set) var statesByProjectID: [UUID: CatalogIntelligenceState] = [:]

    private let database: IntelligenceDatabase
    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var debouncedRefreshTask: Task<Void, Never>?
    private var latestRefreshProjects: [ToolProject] = []
    private var latestIncludeFreshnessEvaluation = true
    private var refreshAgainAfterCurrent = false

    init(database: IntelligenceDatabase = .shared) {
        self.database = database
    }

    func state(for project: ToolProject) -> CatalogIntelligenceState {
        statesByProjectID[project.id] ?? CatalogIntelligenceState(
            projectID: project.id,
            repositoryID: nil,
            hasIntelligence: false,
            cloneStatus: nil,
            analysisStatus: .notFetched,
            runbookBadge: .noIntelligence,
            runbookFreshness: nil,
            runbookLastGeneratedAt: nil,
            runbookLastExportedAt: nil,
            activeJobStatus: nil,
            staleReason: nil,
            analysisErrorMessage: nil
        )
    }

    func refresh(projects: [ToolProject], includeFreshnessEvaluation: Bool = true) {
        latestRefreshProjects = projects
        latestIncludeFreshnessEvaluation = includeFreshnessEvaluation
        debouncedRefreshTask?.cancel()
        debouncedRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            performRefreshNow()
        }
    }

    /// Starts at most one background poll loop for the whole app session.
    func ensurePolling(projects: @escaping @MainActor () -> [ToolProject]) {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                refresh(projects: projects(), includeFreshnessEvaluation: false)
                try? await Task.sleep(nanoseconds: 12_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        debouncedRefreshTask?.cancel()
        debouncedRefreshTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func performRefreshNow() {
        if refreshTask != nil {
            refreshAgainAfterCurrent = true
            return
        }
        let snapshotProjects = latestRefreshProjects
        let includeFreshness = latestIncludeFreshnessEvaluation
        refreshTask = Task { @MainActor in
            let built = await Task.detached(priority: .utility) {
                CatalogIntelligenceStateService.buildStates(for: snapshotProjects,
                                                              database: IntelligenceDatabase.shared,
                                                              includeFreshnessEvaluation: includeFreshness)
            }.value
            refreshTask = nil
            guard !Task.isCancelled else { return }
            applyBuiltStates(built)
            if refreshAgainAfterCurrent {
                refreshAgainAfterCurrent = false
                performRefreshNow()
            }
        }
    }

    private func applyBuiltStates(_ built: [UUID: CatalogIntelligenceState]) {
        guard built != statesByProjectID else { return }
        statesByProjectID = built
    }
}
