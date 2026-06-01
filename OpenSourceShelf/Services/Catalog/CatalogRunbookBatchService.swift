import AppKit
import Foundation

struct CatalogRunbookBatchResult: Equatable {
    var started: Int
    var skippedNoIntelligence: Int
    var skippedFresh: Int
    var skippedGenerating: Int
    var skippedNoRunbook: Int
    var exported: Int
    var failed: Int

    var summaryMessage: String {
        var parts: [String] = []
        if started > 0 { parts.append("\(started) queued") }
        if exported > 0 { parts.append("\(exported) exported") }
        let skipped = skippedNoIntelligence + skippedFresh + skippedGenerating + skippedNoRunbook
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty { return "Nothing to do for the selected projects." }
        return parts.joined(separator: ", ")
    }
}

enum CatalogRunbookBatchService {
    static func generateRunbooks(for projects: [ToolProject],
                                 force: Bool = false,
                                 database: IntelligenceDatabase = .shared) -> CatalogRunbookBatchResult {
        var result = CatalogRunbookBatchResult(started: 0,
                                               skippedNoIntelligence: 0,
                                               skippedFresh: 0,
                                               skippedGenerating: 0,
                                               skippedNoRunbook: 0,
                                               exported: 0,
                                               failed: 0)

        for project in projects {
            guard let repositoryID = IntelligenceRepositoryBridge.repositoryID(for: project, database: database) else {
                result.skippedNoIntelligence += 1
                continue
            }

            if RunbookGenerationCoordinator.isGenerating(repositoryID: repositoryID, database: database) {
                result.skippedGenerating += 1
                continue
            }

            if !force,
               let runbook = try? database.fetchLatestRunbook(repositoryID: repositoryID),
               case .fresh = (try? RepositoryRunbookService.evaluateFreshness(runbook,
                                                                             repositoryID: repositoryID,
                                                                             database: database)) ?? .neverGenerated {
                result.skippedFresh += 1
                continue
            }

            do {
                _ = try RepositoryRunbookService.enqueueGeneration(repositoryID: repositoryID,
                                                                   force: force,
                                                                   database: database)
                result.started += 1
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    static func regenerateStaleRunbooks(for projects: [ToolProject],
                                        database: IntelligenceDatabase = .shared) -> CatalogRunbookBatchResult {
        var result = CatalogRunbookBatchResult(started: 0,
                                               skippedNoIntelligence: 0,
                                               skippedFresh: 0,
                                               skippedGenerating: 0,
                                               skippedNoRunbook: 0,
                                               exported: 0,
                                               failed: 0)

        for project in projects {
            guard let repositoryID = IntelligenceRepositoryBridge.repositoryID(for: project, database: database) else {
                result.skippedNoIntelligence += 1
                continue
            }

            guard let runbook = try? database.fetchLatestRunbook(repositoryID: repositoryID) else {
                result.skippedNoRunbook += 1
                continue
            }

            let freshness = (try? RepositoryRunbookService.evaluateFreshness(runbook,
                                                                           repositoryID: repositoryID,
                                                                           database: database)) ?? .neverGenerated
            guard freshness.isStale else {
                result.skippedFresh += 1
                continue
            }

            if RunbookGenerationCoordinator.isGenerating(repositoryID: repositoryID, database: database) {
                result.skippedGenerating += 1
                continue
            }

            do {
                _ = try RepositoryRunbookService.enqueueGeneration(repositoryID: repositoryID,
                                                                   force: false,
                                                                   database: database)
                result.started += 1
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    @discardableResult
    static func exportSelectedRunbooks(for projects: [ToolProject],
                                       database: IntelligenceDatabase = .shared) -> CatalogRunbookBatchResult {
        var result = CatalogRunbookBatchResult(started: 0,
                                               skippedNoIntelligence: 0,
                                               skippedFresh: 0,
                                               skippedGenerating: 0,
                                               skippedNoRunbook: 0,
                                               exported: 0,
                                               failed: 0)

        let panel = NSOpenPanel()
        panel.title = "Export Selected Runbooks"
        panel.message = "Choose a folder. reshelf will export one markdown file per selected repo."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let baseURL = panel.url else {
            return result
        }

        for project in projects {
            guard let repository = IntelligenceRepositoryBridge.findIntelligenceRepository(for: project, database: database),
                  let runbook = try? database.fetchLatestRunbook(repositoryID: repository.id) else {
                if IntelligenceRepositoryBridge.repositoryID(for: project, database: database) == nil {
                    result.skippedNoIntelligence += 1
                } else {
                    result.skippedNoRunbook += 1
                }
                continue
            }

            let filename = RunbookExportService.defaultFilename(for: repository, generatedAt: runbook.updatedAt)
            let destination = uniqueFileURL(base: baseURL, filename: filename)
            do {
                try runbook.markdown.write(to: destination, atomically: true, encoding: .utf8)
                try RepositoryRunbookService.recordExport(runbookID: runbook.id, database: database)
                result.exported += 1
            } catch {
                result.failed += 1
            }
        }

        if result.exported > 0 {
            NSWorkspace.shared.activateFileViewerSelecting([baseURL])
            AppRefreshBus.emit(.runbookExported(repositoryID: nil, exportedCount: result.exported))
            AppRefreshBus.emit(.catalogStateUpdated)
        }

        return result
    }

    static func emitBatchGenerateEvent(for result: CatalogRunbookBatchResult) {
        let skipped = result.skippedNoIntelligence + result.skippedFresh + result.skippedGenerating + result.skippedNoRunbook
        if result.started > 0 {
            AppRefreshBus.emit(.batchRunbooksQueued(started: result.started, skipped: skipped))
        }
        AppRefreshBus.emit(.queueUpdated)
        AppRefreshBus.emit(.catalogStateUpdated)
    }

    private static func uniqueFileURL(base: URL, filename: String) -> URL {
        var candidate = base.appendingPathComponent(filename)
        var index = 2
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            candidate = base.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }
}
