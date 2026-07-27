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
    static func writeSnapshot(_ projects: [ToolProject]) {
        guard !projects.isEmpty else { return }
        guard let data = try? CatalogExportService.encode(projects) else { return }

        if let newest = snapshotURLs().first,
           let existing = try? Data(contentsOf: newest),
           projectCount(in: existing) == projects.count,
           existing.count == data.count {
            return // unchanged since last snapshot
        }

        let url = backupsDirectory.appendingPathComponent("catalog-\(timestamp()).json")
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

        CatalogImportService.merge(snapshot.projects, into: context)
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
        return CatalogImportService.merge(incoming, into: context)
    }

    // MARK: - Helpers

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
