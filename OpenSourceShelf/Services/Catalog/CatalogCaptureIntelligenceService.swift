import Foundation

/// Links a newly saved catalog project to the GRDB intelligence layer (metadata only — no clone).
enum CatalogCaptureIntelligenceService {
    static func upsertFromCatalogSave(_ project: ToolProject) {
        let githubURL = project.githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !githubURL.isEmpty else { return }

        Task {
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
