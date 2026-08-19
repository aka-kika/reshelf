import Foundation

/// Links a newly saved catalog project to the GRDB intelligence layer (metadata only — no clone).
enum CatalogCaptureIntelligenceService {
    @MainActor
    static func upsertFromCatalogSave(_ project: ToolProject) {
        let githubURL = project.githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !githubURL.isEmpty else { return }

        // @MainActor task: the bridge reads the SwiftData model (main-context
        // bound), and reading a @Model off the main actor races main-thread
        // writes — e.g. Capture Assist filling the same row right after save.
        // The GitHub round trip in ingestMetadata still suspends off-main.
        Task { @MainActor in
            do {
                try IntelligenceDatabase.shared.initialize()
                _ = try IntelligenceRepositoryBridge.createIntelligenceRepositoryIfNeeded(for: project)
                _ = try await RepositoryIngestionService.ingestMetadata(githubURL: githubURL)
                AppRefreshBus.emit(.catalogStateUpdated)
            } catch {
                #if DEBUG
                print("[reshelf] Catalog intelligence upsert failed: \(error)")
                #endif
            }
        }
    }
}
