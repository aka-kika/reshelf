import Foundation
import SwiftData

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

// Set before anything can write: never ~/reshelf.
let backups = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: backups)
CatalogBackupService.backupsDirectoryOverride = backups
CatalogBackupService.debounceDelay = 0.3

var containers: [ModelContainer] = []

@MainActor
func makeContext() throws -> ModelContext {
    let container = try ModelContainer(for: ToolProject.self, CatalogFolder.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    containers.append(container)
    return ModelContext(container)
}

@MainActor
func all(_ context: ModelContext) -> [ToolProject] {
    (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
}

func files() -> [URL] { CatalogBackupService.snapshotURLs() }
func onMainThread() -> Bool { Thread.isMainThread }

func settle() async {
    try? await Task.sleep(nanoseconds: 700_000_000)
    CatalogBackupService.waitForWrites()
}

@MainActor
func run() async throws {
    let ctx = try makeContext()

    // 1. A bulk import: 25 inserts, each one a count change, close together.
    for i in 1...25 {
        ctx.insert(ToolProject(name: "repo\(i)", githubURL: "https://github.com/test/repo\(i)", status: .collector))
        try ctx.save()
        CatalogBackupService.scheduleSnapshot(from: ctx)
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    check("nothing written while changes keep coming", files().isEmpty)
    await settle()
    check("one snapshot for the whole bulk import", files().count == 1)
    if let only = files().first {
        check("it holds the catalog as it ended", CatalogBackupService.projects(in: only).count == 25)
    }

    // 2. A labelled safety backup is on disk the moment the call returns,
    //    even with a routine snapshot waiting.
    ctx.insert(ToolProject(name: "repo26", githubURL: "https://github.com/test/repo26", status: .collector))
    try ctx.save()
    CatalogBackupService.scheduleSnapshot(from: ctx)
    let before = files().count
    CatalogBackupService.writeSnapshot(all(ctx), reason: "Before moving 3 repos to Yard Sale")
    check("labelled backup written at once", files().count == before + 1
          && CatalogBackupService.reason(in: files()[0]) == "Before moving 3 repos to Yard Sale")
    await settle()
    check("the waiting snapshot of the same state is skipped as unchanged", files().count == before + 1)

    // 3. Quit: written at once, and the waiting routine snapshot is dropped.
    ctx.insert(ToolProject(name: "repo27", githubURL: "https://github.com/test/repo27", status: .collector))
    try ctx.save()
    CatalogBackupService.scheduleSnapshot(from: ctx)
    let beforeQuit = files().count
    CatalogBackupService.writeSnapshotNow(all(ctx))
    check("quit backup written at once", files().count == beforeQuit + 1
          && CatalogBackupService.projects(in: files()[0]).count == 27)
    all(ctx).first?.notes = "edited after quit write"
    try ctx.save()
    await settle()
    check("the waiting snapshot was cancelled by the quit write", files().count == beforeQuit + 1)

    // 4. The file is the export format: export decoding and folders work.
    let folder = CatalogFolder(name: "Agents", sortIndex: 0)
    ctx.insert(folder)
    all(ctx).first?.folderID = folder.id
    try ctx.save()
    CatalogBackupService.scheduleSnapshot(from: ctx)
    await settle()
    let newest = files()[0]
    check("routine snapshot carries folders", CatalogBackupService.folders(in: newest).map(\.name) == ["Agents"])
    check("routine snapshot has no label", CatalogBackupService.reason(in: newest) == nil)

    // 5. The Restore list: counts and labels, read off the main thread.
    try Data("not json".utf8).write(to: backups.appendingPathComponent("catalog-2000-01-01-000000.json"))
    let summaries = await Task.detached { () -> ([CatalogBackupService.SnapshotSummary], Bool) in
        (CatalogBackupService.snapshotSummaries(), onMainThread())
    }.value
    check("list read off the main thread", summaries.1 == false)
    check("list has every file, newest first", summaries.0.map(\.url) == files())
    check("counts match the full read", summaries.0.allSatisfy {
        $0.count == CatalogBackupService.projects(in: $0.url).count })
    check("labels match", summaries.0.map(\.reason) == files().map { CatalogBackupService.reason(in: $0) })
    check("an unreadable file lists as 0", summaries.0.last?.count == 0)

    // 6. A shelf move or a note does not change the project count. Saving
    //    through CatalogSave still schedules the snapshot (8206).
    let edited = all(ctx).first!
    edited.notes = "saved from the shelf"
    edited.status = .topShelf
    let beforeEdit = files().count
    check("in-place save reports success", CatalogSave.save(ctx, "the note"))
    check("in-place edit waits out the debounce", files().count == beforeEdit)
    await settle()
    let newestEdit = files()[0]
    let savedNote = CatalogBackupService.projects(in: newestEdit).contains { $0.notes == "saved from the shelf" }
    check("in-place edit is in the newest snapshot", files().count == beforeEdit + 1 && savedNote)

    // 7. Deleting a folder writes a labelled backup first, then ungroups (8504).
    let grouped = all(ctx).first!
    let box = CatalogFolder(name: "Batch", sortIndex: 0)
    ctx.insert(box)
    grouped.folderID = box.id
    try ctx.save()
    let ungrouped = CatalogFolderService.delete(box, in: ctx)
    check("folder delete writes a labelled backup", ungrouped == 1
          && CatalogBackupService.reason(in: files()[0]) == "Before deleting folder Batch")
    check("folder delete clears membership", grouped.folderID == nil)
    let left = CatalogFolderService.folders(in: ctx).map(\.name)
    check("folder delete removes the folder", !left.contains("Batch"))

    // 8. A backup that cannot be written reports failure (4fc5). The caller
    //    stops the delete or the Yard Sale move instead of saying it was saved.
    func catalogFiles(in dir: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("catalog-") }.count
    }
    let blocker = backups.appendingPathComponent("not-a-folder")
    try Data("x".utf8).write(to: blocker)
    let beforeBlock = catalogFiles(in: backups)
    CatalogBackupService.backupsDirectoryOverride = blocker
    let wrote = CatalogBackupService.writeSnapshot(all(ctx), reason: "Before removing one")
    check("a backup that cannot be written returns false", wrote == false)
    check("a failed backup writes no file", catalogFiles(in: backups) == beforeBlock)
}

try await run()
try? FileManager.default.removeItem(at: backups)
exit(failures == 0 ? 0 : 1)
