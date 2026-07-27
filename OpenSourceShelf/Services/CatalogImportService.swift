import Foundation
import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Reads a catalog JSON file (a manual export or an automatic backup — same
/// schema) and merges it into the catalog. The counterpart to
/// `CatalogExportService`, and the single merge path shared with
/// `CatalogBackupService`'s restore.
///
/// Merging is additive by default: projects already in the catalog are matched
/// by GitHub URL (falling back to id) and left alone, so importing twice, or
/// importing a partly-overlapping catalog, never duplicates or clobbers.
/// Opting into `updatingExisting` overwrites matched projects' metadata with
/// the file's version — for moving a catalog between machines.
enum CatalogImportService {

    /// What an import file would do to the current catalog, computed before
    /// anything is written so the user can see it and confirm.
    struct Plan {
        let sourceURL: URL
        /// Rows with no counterpart in the catalog — always inserted.
        let additions: [CatalogProjectDTO]
        /// Rows matching an existing project — inserted only if updating.
        let matches: [(row: CatalogProjectDTO, existing: ToolProject)]

        var isEmpty: Bool { additions.isEmpty && matches.isEmpty }
    }

    struct Result {
        let added: Int
        let updated: Int
        let skipped: Int
    }

    // MARK: - Picking a file

    /// Presents an open panel and decodes the chosen file. Returns `nil` when
    /// the user cancels; shows an alert (and returns `nil`) when the file isn't
    /// a readable reshelf catalog.
    @MainActor
    static func presentOpenPanel() -> (url: URL, rows: [CatalogProjectDTO])? {
        let panel = NSOpenPanel()
        panel.title = "Import Catalog"
        panel.message = "Choose a reshelf catalog JSON file to import."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = CatalogBackupService.backupsDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let rows = try CatalogExportService.decode(data)
            guard !rows.isEmpty else {
                presentAlert(title: "Nothing to Import",
                             message: "\(url.lastPathComponent) is a valid reshelf catalog file, but it contains no projects.")
                return nil
            }
            return (url, rows)
        } catch {
            presentAlert(title: "Couldn't Read That File",
                         message: "\(url.lastPathComponent) isn't a reshelf catalog export. Choose a JSON file written by Export Catalog as JSON, or one from ~/reshelf/backups.")
            return nil
        }
    }

    // MARK: - Planning

    @MainActor
    static func plan(rows: [CatalogProjectDTO], sourceURL: URL, context: ModelContext) -> Plan {
        let existing = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        var byKey: [String: ToolProject] = [:]
        for project in existing {
            byKey[key(forURL: project.githubURL, id: project.id.uuidString)] = project
        }

        var additions: [CatalogProjectDTO] = []
        var matches: [(CatalogProjectDTO, ToolProject)] = []
        // Rows can collide with each other too (two entries, same repo). Track
        // keys claimed by earlier rows so the second one counts as a match, not
        // a second insert.
        var claimed = Set<String>()

        for row in rows {
            let k = key(forURL: row.githubURL, id: row.id)
            if let match = byKey[k] {
                matches.append((row, match))
            } else if claimed.contains(k) {
                continue
            } else {
                claimed.insert(k)
                additions.append(row)
            }
        }
        return Plan(sourceURL: sourceURL, additions: additions, matches: matches)
    }

    // MARK: - Applying

    /// Inserts every addition, and — when `updatingExisting` — overwrites the
    /// matched projects with the file's values. Takes a backup snapshot first so
    /// an unwanted import is always recoverable from Restore from Backup.
    @MainActor
    @discardableResult
    static func apply(_ plan: Plan, updatingExisting: Bool, into context: ModelContext) -> Result {
        let before = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        CatalogBackupService.writeSnapshot(before)

        for row in plan.additions {
            context.insert(row.makeToolProject())
        }
        if updatingExisting {
            for (row, existing) in plan.matches {
                row.apply(to: existing)
            }
        }
        if !plan.additions.isEmpty || (updatingExisting && !plan.matches.isEmpty) {
            try? context.save()
        }

        return Result(added: plan.additions.count,
                      updated: updatingExisting ? plan.matches.count : 0,
                      skipped: updatingExisting ? 0 : plan.matches.count)
    }

    /// Additive merge used by backup restore: inserts rows whose key isn't
    /// already in the catalog. Returns the number inserted.
    @MainActor
    @discardableResult
    static func merge(_ rows: [CatalogProjectDTO], into context: ModelContext) -> Int {
        let plan = plan(rows: rows, sourceURL: URL(fileURLWithPath: "/"), context: context)
        return apply(plan, updatingExisting: false, into: context).added
    }

    // MARK: - Helpers

    /// Identity for dedupe: the GitHub URL, normalized, since that's what
    /// actually identifies a project across machines (ids diverge when the same
    /// repo was captured separately on each Mac). Falls back to the id for rows
    /// with no URL.
    static func key(forURL url: String, id: String) -> String {
        let normalized = url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return normalized.isEmpty ? "id:\(id)" : normalized
    }

    @MainActor
    private static func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
