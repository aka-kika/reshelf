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
        /// Folders named in the file. Empty for pre-folders exports.
        let folders: [CatalogFolderDTO]

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
    static func presentOpenPanel() -> (url: URL, rows: [CatalogProjectDTO], folders: [CatalogFolderDTO])? {
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
            let folders = (try? CatalogExportService.decodeFolders(data)) ?? []
            return (url, rows, folders)
        } catch {
            presentAlert(title: "Couldn't Read That File",
                         message: "\(url.lastPathComponent) isn't a reshelf catalog export. Choose a JSON file written by Export Catalog as JSON, or one from ~/reshelf/backups.")
            return nil
        }
    }

    // MARK: - Planning

    @MainActor
    static func plan(rows: [CatalogProjectDTO], folders: [CatalogFolderDTO] = [], sourceURL: URL, context: ModelContext) -> Plan {
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
        return Plan(sourceURL: sourceURL, additions: additions, matches: matches, folders: folders)
    }

    // MARK: - Applying

    /// Inserts every addition, and — when `updatingExisting` — overwrites the
    /// matched projects with the file's values. Takes a backup snapshot first so
    /// an unwanted import is always recoverable from Restore from Backup.
    @MainActor
    @discardableResult
    static func apply(_ plan: Plan, updatingExisting: Bool, into context: ModelContext) -> Result {
        let before = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        CatalogBackupService.writeSnapshot(before, folders: CatalogFolderService.folders(in: context))

        // Folders first, so the projects inserted below can be remapped onto
        // local folders that are guaranteed to exist.
        let folderMap = resolveFolders(plan.folders, in: context)

        for row in plan.additions {
            let project = row.makeToolProject()
            project.folderID = row.folderID.flatMap { folderMap[$0] }
            context.insert(project)
        }
        if updatingExisting {
            for (row, existing) in plan.matches {
                row.apply(to: existing)
                // Only when the file carries a folder for this project — an older
                // export with no key must not eject it from a folder it's in
                // locally, same rule as personalNote.
                if let localID = row.folderID.flatMap({ folderMap[$0] }) {
                    existing.folderID = localID
                }
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
    static func merge(_ rows: [CatalogProjectDTO],
                      folders: [CatalogFolderDTO] = [],
                      into context: ModelContext) -> Int {
        let plan = plan(rows: rows, folders: folders,
                        sourceURL: URL(fileURLWithPath: "/"), context: context)
        return apply(plan, updatingExisting: false, into: context).added
    }

    /// Maps each folder id in the file to the id of the local folder that should
    /// hold its projects, creating folders the catalog doesn't have yet.
    ///
    /// Matching is by **name**, case-insensitively, not by id: two Macs that each
    /// created "Photos app" independently should converge on one folder. Matching
    /// on id instead would duplicate every folder on the second machine, which is
    /// both worse and harder to undo than a merge.
    @MainActor
    private static func resolveFolders(_ rows: [CatalogFolderDTO], in context: ModelContext) -> [String: UUID] {
        guard !rows.isEmpty else { return [:] }
        var map: [String: UUID] = [:]
        for row in rows {
            // `create` already returns the existing folder on a name collision,
            // so this is both the match and the create path.
            if let folder = CatalogFolderService.create(name: row.name, in: context) {
                map[row.id] = folder.id
            }
        }
        return map
    }

    // MARK: - Helpers

    /// Identity for dedupe: the GitHub URL, normalized, since that's what
    /// actually identifies a project across machines (ids diverge when the same
    /// repo was captured separately on each Mac). Falls back to the id for rows
    /// with no URL.
    static func key(forURL url: String, id: String) -> String {
        // Same normalizer as Quick Capture's duplicate guard: URLs differing
        // only by www. / .git / /tree/... must collapse to one key, or an
        // import from another machine duplicates rows despite the additive-
        // merge "never duplicates" contract.
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { return "id:\(id)" }
        return IconFetcher.repoDedupKey(for: url)
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
