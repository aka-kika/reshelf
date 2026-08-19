import Foundation
import SwiftData

/// Durable safety net for the catalog. Writes timestamped JSON snapshots to
/// `~/reshelf/backups/` on every meaningful change, keeps the most recent N, and
/// — critically — can auto-restore if the catalog ever comes up unexpectedly empty
/// (the exact failure that previously wiped data and silently re-seeded).
///
/// Snapshots use the same schema as manual JSON export, so any backup is a valid
/// export and any export is a valid restore source.
enum CatalogBackupService {
    /// How many snapshots to retain. Old ones are pruned oldest-first.
    static let maxSnapshots = 30

    static var backupsDirectory: URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("reshelf", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - Writing

    /// Writes a snapshot of the given projects, then prunes old ones. No-ops when
    /// the catalog is empty (never overwrite history with nothing) or when the
    /// newest snapshot is byte-identical (avoid churn on no-op saves).
    /// Folders ride along so a restore doesn't silently ungroup the catalog.
    static func writeSnapshot(_ projects: [ToolProject], folders: [CatalogFolder] = []) {
        guard !projects.isEmpty else { return }
        guard let data = try? CatalogExportService.encode(projects, folders: folders) else { return }

        // Skip only when the *content* is genuinely unchanged. This used to compare
        // byte lengths, which quietly failed: an edit that swaps one value for
        // another of the same length leaves the file exactly as long, so real
        // changes looked identical and no snapshot was written. Compare the encoded
        // projects instead — and not the whole file, whose `exportedAt` differs on
        // every call and would make every comparison report a change.
        if let newest = snapshotURLs().first,
           let existing = try? Data(contentsOf: newest),
           let existingRows = try? CatalogExportService.decode(existing),
           existingRows.count == projects.count,
           fingerprint(of: existingRows) == fingerprint(of: projects.map(CatalogProjectDTO.init)) {
            return // unchanged since last snapshot
        }

        // Never reuse an existing snapshot's name. Two writes can land in the
        // same instant — Remove Duplicate Repos writes its pre-delete safety
        // snapshot and the count-change observer writes the post-delete state
        // in the same runloop tick — and an atomic write to the same filename
        // would replace the safety copy with exactly what it was protecting
        // against.
        var url = backupsDirectory.appendingPathComponent("catalog-\(timestamp()).json")
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = backupsDirectory.appendingPathComponent("catalog-\(timestamp())-\(attempt).json")
            attempt += 1
        }
        do {
            try data.write(to: url, options: .atomic)
            prune()
        } catch {
            #if DEBUG
            print("[reshelf] Backup write failed: \(error)")
            #endif
        }
    }

    private static func prune() {
        let urls = snapshotURLs() // newest first
        guard urls.count > maxSnapshots else { return }
        for url in urls.dropFirst(maxSnapshots) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Reading / restoring

    /// All snapshot files, newest first (filenames are timestamp-sortable).
    static func snapshotURLs() -> [URL] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: backupsDirectory,
                                                 includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("catalog-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func projects(in url: URL) -> [CatalogProjectDTO] {
        guard let data = try? Data(contentsOf: url),
              let projects = try? CatalogExportService.decode(data) else { return [] }
        return projects
    }

    static func folders(in url: URL) -> [CatalogFolderDTO] {
        guard let data = try? Data(contentsOf: url),
              let folders = try? CatalogExportService.decodeFolders(data) else { return [] }
        return folders
    }

    /// The newest snapshot that actually contains projects.
    static func latestNonEmptySnapshot() -> (url: URL, projects: [CatalogProjectDTO])? {
        for url in snapshotURLs() {
            let projects = projects(in: url)
            if !projects.isEmpty { return (url, projects) }
        }
        return nil
    }

    /// Safety net: if the catalog is empty but a backup with data exists, restore
    /// it instead of letting the app seed defaults over a real (but momentarily
    /// missing) catalog. Returns `true` if a restore happened.
    @MainActor
    static func restoreIfCatalogEmpty(context: ModelContext) -> Bool {
        let count = (try? context.fetchCount(FetchDescriptor<ToolProject>())) ?? 0
        guard count == 0, let snapshot = latestNonEmptySnapshot() else { return false }

        CatalogImportService.merge(snapshot.projects, folders: folders(in: snapshot.url), into: context)
        #if DEBUG
        print("[reshelf] Catalog was empty — restored \(snapshot.projects.count) projects from \(snapshot.url.lastPathComponent)")
        #endif
        return true
    }

    /// Restores a chosen snapshot, merging in any projects not already present
    /// (matched by GitHub URL, then id). Returns the number inserted.
    @MainActor
    @discardableResult
    static func restore(from url: URL, into context: ModelContext) -> Int {
        let incoming = projects(in: url)
        guard !incoming.isEmpty else { return 0 }
        return CatalogImportService.merge(incoming, folders: folders(in: url), into: context)
    }

    // MARK: - Helpers

    /// A content digest of the rows only — deliberately excludes the snapshot
    /// wrapper, whose `exportedAt` changes on every encode.
    private static func fingerprint(of rows: [CatalogProjectDTO]) -> Int {
        var hasher = Hasher()
        for row in rows.sorted(by: { $0.id < $1.id }) {
            hasher.combine(row.id)
            hasher.combine(row.name)
            hasher.combine(row.status)
            hasher.combine(row.category)
            hasher.combine(row.stars)
            hasher.combine(row.notes)
            hasher.combine(row.personalNote)
            hasher.combine(row.tags)
            hasher.combine(row.useCases)
            hasher.combine(row.fitScore)
            hasher.combine(row.githubURL)
            hasher.combine(row.lastUpdatedDate)
            hasher.combine(row.lastCheckedDate)
            // Every remaining exported field. Anything the snapshot stores but
            // the fingerprint skips is a field whose edits are never backed up —
            // and that a restore then silently reverts.
            hasher.combine(row.shortDescription)
            hasher.combine(row.longDescription)
            hasher.combine(row.websiteURL)
            hasher.combine(row.license)
            hasher.combine(row.isLocalFirst)
            hasher.combine(row.isSelfHosted)
            hasher.combine(row.addedDate)
            // Moving a project between folders is a real change — without this,
            // a regrouped catalog would look identical and no snapshot would be
            // written, which is the exact bug the content comparison replaced
            // byte-length checking to fix.
            hasher.combine(row.folderID)
        }
        return hasher.finalize()
    }

    private static func projectCount(in data: Data) -> Int {
        (try? CatalogExportService.decode(data).count) ?? -1
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
