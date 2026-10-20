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

    /// Tests point backups at a temp folder; the app never sets this.
    static var backupsDirectoryOverride: URL?

    static var backupsDirectory: URL {
        if let override = backupsDirectoryOverride {
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
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
    /// `reason` labels a safety backup taken before a big change; a labelled
    /// one is always written, even when nothing changed since the newest file,
    /// so Restore from Backup can show "Before …" for every such action.
    /// Synchronous: the file is on disk when this returns, so a safety backup
    /// is in place before the change it protects.
    static func writeSnapshot(_ projects: [ToolProject], folders: [CatalogFolder] = [], reason: String? = nil) {
        guard !projects.isEmpty else { return }
        // Copied on the caller's thread: models must not cross threads.
        let rows = projects.map(CatalogProjectDTO.init)
        let folderRows = folders.map(CatalogFolderDTO.init)
        writeQueue.sync { write(rows, folders: folderRows, reason: reason) }
    }

    // MARK: - Routine snapshots (debounced)

    /// How long the catalog has to stay still before a routine snapshot is
    /// written. A bulk import changes the count once per repo; without the wait
    /// each change wrote a snapshot and 30 kept files were one import's worth.
    static var debounceDelay: TimeInterval = 2

    @MainActor private static var pendingSnapshot: Task<Void, Never>?

    /// Every write goes through here, one at a time. Routine snapshots encode
    /// and write here in the background; labelled and quit writes wait on it.
    private static let writeQueue = DispatchQueue(label: "reshelf.backup-writes", qos: .utility)

    /// Routine snapshot after a change: waits for `debounceDelay` without a
    /// newer call, then copies the catalog on main and writes it off main.
    @MainActor
    static func scheduleSnapshot(from context: ModelContext) {
        pendingSnapshot?.cancel()
        pendingSnapshot = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            pendingSnapshot = nil
            let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
            guard !projects.isEmpty else { return }
            let folders = (try? context.fetch(FetchDescriptor<CatalogFolder>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
            let rows = projects.map(CatalogProjectDTO.init)
            let folderRows = folders.map(CatalogFolderDTO.init)
            writeQueue.async { write(rows, folders: folderRows, reason: nil) }
        }
    }

    /// On quit: drops the waiting routine snapshot and writes now, synchronously.
    @MainActor
    static func writeSnapshotNow(_ projects: [ToolProject], folders: [CatalogFolder] = []) {
        pendingSnapshot?.cancel()
        pendingSnapshot = nil
        writeSnapshot(projects, folders: folders)
    }

    /// Waits until every queued write is on disk (tests).
    static func waitForWrites() {
        writeQueue.sync {}
    }

    /// Runs on `writeQueue` only.
    private static func write(_ rows: [CatalogProjectDTO], folders: [CatalogFolderDTO], reason: String?) {
        guard let data = try? encode(rows, folders: folders, reason: reason) else { return }

        // Skip only when the *content* is genuinely unchanged. This used to compare
        // byte lengths, which quietly failed: an edit that swaps one value for
        // another of the same length leaves the file exactly as long, so real
        // changes looked identical and no snapshot was written. Compare the encoded
        // projects instead — and not the whole file, whose `exportedAt` differs on
        // every call and would make every comparison report a change.
        // Both sides go through the file format: it stores dates to the whole
        // second, so comparing against the live rows (sub-second dates) said
        // "changed" every time and filled the 30 slots with identical copies.
        if reason == nil,
           let newest = snapshotURLs().first,
           let existing = try? Data(contentsOf: newest),
           let existingRows = try? CatalogExportService.decode(existing),
           let newRows = try? CatalogExportService.decode(data),
           existingRows.count == newRows.count,
           fingerprint(of: existingRows) == fingerprint(of: newRows),
           // A new, renamed or reordered folder touches no project row.
           folderFingerprint(of: (try? CatalogExportService.decodeFolders(existing)) ?? [])
               == folderFingerprint(of: folders) {
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

    /// The same file `CatalogExportService.encode` writes, from rows already
    /// copied off the models.
    private static func encode(_ rows: [CatalogProjectDTO], folders: [CatalogFolderDTO], reason: String?) throws -> Data {
        let payload = CatalogSnapshotDTO(
            exportedAt: Date(),
            app: "reshelf",
            version: 1,
            projectCount: rows.count,
            projects: rows,
            folders: folders.isEmpty ? nil : folders,
            reason: reason
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Snapshot of everything in the store right now — for a destructive action
    /// in a view that doesn't hold the whole catalog (the inspector's Delete).
    @MainActor
    static func writeSnapshot(from context: ModelContext, reason: String? = nil) {
        let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        let folders = (try? context.fetch(FetchDescriptor<CatalogFolder>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        writeSnapshot(projects, folders: folders, reason: reason)
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
            // Compare without ".json": with it, "…-035806.json" sorts after its
            // same-second sibling "…-035806-2.json" ("." > "-"), so the older
            // file passed as the newest.
            .sorted { $0.deletingPathExtension().lastPathComponent > $1.deletingPathExtension().lastPathComponent }
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

    static func reason(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? CatalogExportService.decodeReason(data)) ?? nil
    }

    struct SnapshotSummary {
        let url: URL
        let count: Int
        let reason: String?
    }

    /// Count and label of every snapshot, newest first, without building the
    /// project rows. Reads every file: call it off the main thread.
    static func snapshotSummaries() -> [SnapshotSummary] {
        snapshotURLs().map { url in
            let header = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode(SnapshotHeader.self, from: $0) }
            return SnapshotSummary(url: url, count: header?.projects.count ?? 0, reason: header?.reason)
        }
    }

    /// Just enough of a snapshot file for the Restore list.
    private struct SnapshotHeader: Decodable {
        struct Skipped: Decodable { init(from decoder: Decoder) {} }
        let projects: [Skipped]
        let reason: String?
    }

    /// The newest snapshot that actually contains projects.
    static func latestNonEmptySnapshot() -> (url: URL, projects: [CatalogProjectDTO])? {
        for url in snapshotURLs() {
            let projects = projects(in: url)
            if !projects.isEmpty { return (url, projects) }
        }
        return nil
    }

    /// Set when the user removes the last project, so the next launch leaves
    /// the catalog empty instead of restoring the newest backup or seeding the
    /// sample repos (before, an emptied shelf always came back). Cleared as
    /// soon as the catalog has a project again, or the store is replaced.
    private static let emptiedByUserKey = "reshelf.catalogEmptiedByUser"

    static var emptiedByUser: Bool {
        UserDefaults.standard.bool(forKey: emptiedByUserKey)
    }

    static func clearEmptiedByUser() {
        UserDefaults.standard.removeObject(forKey: emptiedByUserKey)
    }

    /// Called on every project-count change while the app runs. A drop to zero
    /// mid-session is a deletion; an empty catalog at launch is not, so it
    /// never sets the flag.
    static func noteProjectCount(old: Int, new: Int) {
        if new == 0, old > 0 {
            UserDefaults.standard.set(true, forKey: emptiedByUserKey)
        } else if new > 0 {
            clearEmptiedByUser()
        }
    }

    /// Safety net: if the catalog is empty but a backup with data exists, restore
    /// it instead of letting the app seed defaults over a real (but momentarily
    /// missing) catalog. Not when the user emptied it on purpose. Returns `true`
    /// if a restore happened.
    @MainActor
    static func restoreIfCatalogEmpty(context: ModelContext) -> Bool {
        let count = (try? context.fetchCount(FetchDescriptor<ToolProject>())) ?? 0
        guard count == 0, !emptiedByUser, let snapshot = latestNonEmptySnapshot() else { return false }

        CatalogImportService.merge(snapshot.projects, folders: folders(in: snapshot.url), into: context)
        #if DEBUG
        print("[reshelf] Catalog was empty — restored \(snapshot.projects.count) projects from \(snapshot.url.lastPathComponent)")
        #endif
        return true
    }

    /// Restores a chosen snapshot: adds the projects the catalog is missing
    /// (matched by GitHub URL, then id) and, with `puttingBackChanges`, gives
    /// the ones it still has their backed-up version again. A backup of the
    /// current state is written first, so a restore can itself be undone.
    @MainActor
    @discardableResult
    static func restore(from url: URL, puttingBackChanges: Bool, into context: ModelContext,
                        snapshotDate: String) -> CatalogImportService.Result {
        let incoming = projects(in: url)
        guard !incoming.isEmpty else { return .init(added: 0, updated: 0, skipped: 0) }
        return CatalogImportService.restore(incoming, folders: folders(in: url),
                                            puttingBackChanges: puttingBackChanges, into: context,
                                            backupReason: "Before restoring the backup from \(snapshotDate)")
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
            hasher.combine(row.fitScoreSetByUser)
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

    private static func folderFingerprint(of folders: [CatalogFolderDTO]) -> [String] {
        folders.map { "\($0.id)|\($0.name)|\($0.sortIndex)" }.sorted()
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
