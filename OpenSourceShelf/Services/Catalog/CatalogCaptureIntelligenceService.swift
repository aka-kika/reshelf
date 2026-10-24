import Foundation

/// Links a newly saved catalog project to the GRDB intelligence layer (metadata only — no clone).
enum CatalogCaptureIntelligenceService {
    /// `prefetched`: the GitHub info the caller just read for this repo, so the
    /// metadata store reuses it instead of asking GitHub a second time (the
    /// unauthenticated limit is 60 requests an hour).
    @MainActor
    static func upsertFromCatalogSave(_ project: ToolProject, prefetched: GitHubRepoInfo? = nil) {
        let githubURL = project.githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !githubURL.isEmpty else { return }
        // The row can be deleted before this task runs, and again while the
        // GitHub read is in flight. Keep the id and re-fetch. Reading a
        // deleted model is a fatal SwiftData error.
        let projectID = project.id
        let context = project.modelContext

        // @MainActor task: the bridge reads the SwiftData model (main-context
        // bound), and reading a @Model off the main actor races main-thread
        // writes — e.g. Capture Assist filling the same row right after save.
        // The GitHub round trip in ingestMetadata still suspends off-main.
        Task { @MainActor in
            guard let context, let live = LiveProject.fetch(projectID, in: context) else { return }
            do {
                try IntelligenceDatabase.shared.initialize()
                _ = try IntelligenceRepositoryBridge.createIntelligenceRepositoryIfNeeded(for: live)
                _ = try await RepositoryIngestionService.ingestMetadata(githubURL: githubURL, prefetched: prefetched)
                guard LiveProject.fetch(projectID, in: context) != nil else { return }
                AppRefreshBus.emit(.catalogStateUpdated)
            } catch {
                #if DEBUG
                print("[reshelf] Catalog intelligence upsert failed: \(error)")
                #endif
            }
        }
    }
}
