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
        /// The file has a `folders` key, even when the list is empty.
        /// An old file without the key must not clear folder membership.
        let recordedFolders: Bool

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
    static func plan(rows: [CatalogProjectDTO], folders: [CatalogFolderDTO] = [],
                     recordedFolders: Bool? = nil, sourceURL: URL, context: ModelContext) -> Plan {
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
        return Plan(sourceURL: sourceURL, additions: additions, matches: matches, folders: folders,
                    recordedFolders: recordedFolders ?? !folders.isEmpty)
    }

    // MARK: - Applying

    /// Inserts every addition, and — when `updatingExisting` — overwrites the
    /// matched projects with the file's values. Takes a backup snapshot first so
    /// an unwanted import is always recoverable from Restore from Backup.
    @MainActor
    @discardableResult
    static func apply(_ plan: Plan, updatingExisting: Bool, into context: ModelContext,
                      backupReason: String? = nil) -> Result {
        let before = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        CatalogBackupService.writeSnapshot(before, folders: CatalogFolderService.folders(in: context),
                                           reason: backupReason ?? "Before importing \(plan.sourceURL.lastPathComponent)")

        // Folders first, so the projects inserted below can be remapped onto
        // local folders that are guaranteed to exist.
        let folderMap = resolveFolders(plan.folders, in: context)

        // A row keeps the file's id unless a repo here (or an earlier row in
        // this batch) already has it: after a repo's GitHub URL was edited, an
        // older backup no longer matches it by URL, and reusing its id would
        // leave two rows with one id (selection and the inspector pick either).
        var usedIDs = Set(before.map(\.id))
        for row in plan.additions {
            let project = row.makeToolProject()
            if usedIDs.contains(project.id) { project.id = UUID() }
            usedIDs.insert(project.id)
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
            CatalogSave.save(context)
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
        return apply(plan, updatingExisting: false, into: context,
                     backupReason: "Before restoring a backup").added
    }

    /// Restore from Backup. Always adds the repos the backup has and the
    /// catalog lost. With `puttingBackChanges`, repos still in the catalog get
    /// the backup's version back too (shelf, tags, notes, folder) — the undo
    /// for a Yard Sale move, an import that updated rows, or a duplicate merge.
    /// Only rows that really differ are touched and counted.
    @MainActor
    @discardableResult
    static func restore(_ rows: [CatalogProjectDTO],
                        folders: [CatalogFolderDTO],
                        puttingBackChanges: Bool,
                        into context: ModelContext,
                        backupReason: String,
                        foldersWereRecorded: Bool = false) -> Result {
        let full = plan(rows: rows, folders: folders, recordedFolders: foldersWereRecorded,
                        sourceURL: URL(fileURLWithPath: "/"), context: context)
        let changed = changedMatches(in: full, context: context)
        // Only folders a restored repo actually uses. Creating every folder in
        // the file brought back folders she had deleted, even when the sheet
        // said nothing was restored.
        var usedFolderIDs = Set(full.additions.compactMap(\.folderID))
        if puttingBackChanges {
            usedFolderIDs.formUnion(changed.compactMap { $0.row.folderID })
        }
        let usedFolders = folders.filter { usedFolderIDs.contains($0.id) }
        // Additions only. Put-back is not a full overwrite: name, links,
        // description and category stay. `apply` still writes the safety backup.
        let additions = Plan(sourceURL: full.sourceURL, additions: full.additions,
                             matches: [], folders: usedFolders, recordedFolders: full.recordedFolders)
        let result = apply(additions, updatingExisting: false, into: context, backupReason: backupReason)
        var updated = 0
        if puttingBackChanges && !changed.isEmpty {
            let localFolderIDs = Dictionary(
                CatalogFolderService.folders(in: context).map { ($0.name.lowercased(), $0.id) },
                uniquingKeysWith: { first, _ in first })
            let fileFolderNames = Dictionary(
                folders.map { ($0.id, $0.name.lowercased()) },
                uniquingKeysWith: { first, _ in first })
            for (row, existing) in changed {
                row.applyPutBack(to: existing)
                // An older backup with no folder list leaves membership alone.
                // One that records folders can also take a repo back out.
                if full.recordedFolders {
                    if let name = row.folderID.flatMap({ fileFolderNames[$0] }),
                       let local = localFolderIDs[name] {
                        existing.folderID = local
                    } else {
                        existing.folderID = nil
                    }
                }
                updated += 1
            }
            CatalogSave.save(context)
        }
        return Result(added: result.added, updated: updated,
                      skipped: full.matches.count - updated)
    }

    /// Matched rows whose backup version differs from the catalog's, folder
    /// included (compared by name, the way folders are matched on import).
    @MainActor
    static func changedMatches(in plan: Plan, context: ModelContext) -> [(row: CatalogProjectDTO, existing: ToolProject)] {
        let localFolderNames = Dictionary(
            CatalogFolderService.folders(in: context).map { ($0.id, $0.name.lowercased()) },
            uniquingKeysWith: { first, _ in first })
        let fileFolderNames = Dictionary(
            plan.folders.map { ($0.id, $0.name.lowercased()) },
            uniquingKeysWith: { first, _ in first })
        return plan.matches.filter { row, existing in
            if row.putBackDiffers(from: existing) { return true }
            guard plan.recordedFolders else { return false }
            let fileFolder = row.folderID.flatMap { fileFolderNames[$0] }
            let localFolder = existing.folderID.flatMap { localFolderNames[$0] }
            return fileFolder != localFolder
        }
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
        return GitHubRepositoryURL.dedupKey(for: url)
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
