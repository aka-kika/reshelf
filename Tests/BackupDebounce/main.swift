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

    // Renaming onto another folder's name, ignoring case, is refused (1817).
    let photos = CatalogFolderService.create(name: "Photos", in: ctx)!
    let other = CatalogFolderService.create(name: "Notes", in: ctx)!
    check("rename refuses a case-insensitive clash",
          !CatalogFolderService.rename(other, to: "photos", in: ctx) && other.name == "Notes")
    check("rename still accepts a free name",
          CatalogFolderService.rename(other, to: "Field notes", in: ctx) && other.name == "Field notes")
    _ = photos

    // 8. Labelled backups are not pruned with the 30 routine ones (7aa7).
    check("labelled backup is kept",
          CatalogBackupService.writeSnapshot(all(ctx), reason: "Before removing keep-me"))
    for i in 0..<35 {
        all(ctx)[0].notes = "wave \(i)"
        _ = CatalogBackupService.writeSnapshot(all(ctx))
    }
    let labelledKept = files().contains { CatalogBackupService.reason(in: $0) == "Before removing keep-me" }
    let routineCount = files().filter { CatalogBackupService.reason(in: $0) == nil }.count
    check("a labelled backup survives the routine prune", labelledKept)
    check("routine backups stay at 30", routineCount == 30)

    // 8b. Labelled backups stop at 40, told apart by name (329a). A 1.16.0
    //     labelled file (no suffix) is renamed, not deleted, when it ages out.
    let legacyName = backups.appendingPathComponent("catalog-2001-01-01-000000.json")
    try FileManager.default.copyItem(
        at: files().first { CatalogBackupService.reason(in: $0) == "Before removing keep-me" }!,
        to: legacyName)
    all(ctx)[0].notes = "push the old file out"
    _ = CatalogBackupService.writeSnapshot(all(ctx))
    let renamedLegacy = backups.appendingPathComponent(
        "catalog-2001-01-01-000000\(CatalogBackupService.labelledSuffix).json")
    check("an old unsuffixed labelled file is renamed, not deleted as routine",
          !FileManager.default.fileExists(atPath: legacyName.path)
          && CatalogBackupService.reason(in: renamedLegacy) == "Before removing keep-me")
    for i in 0..<45 {
        all(ctx)[0].notes = "labelled \(i)"
        _ = CatalogBackupService.writeSnapshot(all(ctx), reason: "Before wave \(i)")
    }
    let labelledFiles = files().filter(CatalogBackupService.isLabelled)
    check("labelled backups stay at \(CatalogBackupService.maxLabelledSnapshots)",
          labelledFiles.count == CatalogBackupService.maxLabelledSnapshots)
    check("every labelled file has a label", labelledFiles.allSatisfy { CatalogBackupService.reason(in: $0) != nil })
    check("the newest labelled backups are the ones kept",
          CatalogBackupService.reason(in: labelledFiles[0]) == "Before wave 44"
          && !labelledFiles.contains { CatalogBackupService.reason(in: $0) == "Before wave 4" })
    check("routine backups are still 30", files().filter { !CatalogBackupService.isLabelled($0) }.count == 30)

    // 9. A backup that cannot be written reports failure (4fc5). The caller
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

    // 10. c1c8: fits activity (a run, Hide, Keep, a filter) changes only her
    //     repos. It replaces the newest routine file instead of adding one,
    //     so it never pushes shelf history out of the 30 routine slots.
    let fitsDir = backups.appendingPathComponent("fits-only")
    CatalogBackupService.backupsDirectoryOverride = fitsDir
    var note = "run 0"
    CatalogBackupService.myReposSource = { _, _ in
        [MyRepoDTO(fullName: "kika/app", githubURL: "https://github.com/kika/app", summary: "",
                   addedAt: Date(timeIntervalSince1970: 0), sortIndex: 0, lastRunAt: nil,
                   previousRunAt: nil, lastRunNote: note, fits: [])]
    }
    func myRepoNote(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? CatalogExportService.decodeMyRepos(data))?.first?.lastRunNote
    }
    all(ctx)[0].notes = "shelf state A"
    _ = CatalogBackupService.writeSnapshot(all(ctx))
    all(ctx)[0].notes = "shelf state B"
    _ = CatalogBackupService.writeSnapshot(all(ctx))
    check("two catalog changes, two routine files", files().count == 2)
    for i in 1...40 {
        note = "run \(i)"
        _ = CatalogBackupService.writeSnapshot(all(ctx))
    }
    check("40 fits-only saves add no routine file", files().count == 2)
    check("the newest file holds the latest fits", files().first.flatMap(myRepoNote) == "run 40")
    check("the newest file still holds the current catalog",
          CatalogBackupService.projects(in: files()[0]).contains { $0.notes == "shelf state B" })
    check("the older shelf state is still there",
          CatalogBackupService.projects(in: files()[1]).contains { $0.notes == "shelf state A" })
    _ = CatalogBackupService.writeSnapshot(all(ctx))
    check("an unchanged save writes nothing", files().count == 2)
    // A labelled file is never the one replaced.
    _ = CatalogBackupService.writeSnapshot(all(ctx), reason: "Before removing kika/app")
    note = "after the labelled one"
    _ = CatalogBackupService.writeSnapshot(all(ctx))
    check("a fits-only save after a labelled backup adds a routine file", files().count == 4)
    check("the labelled backup is kept",
          files().contains { CatalogBackupService.reason(in: $0) == "Before removing kika/app" })
    // A catalog change after fits activity is a new file again.
    all(ctx)[0].notes = "shelf state C"
    // With the folders, as the debounced path below copies them.
    let folders = (try? ctx.fetch(FetchDescriptor<CatalogFolder>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    _ = CatalogBackupService.writeSnapshot(all(ctx), folders: folders)
    check("a catalog change still adds a file", files().count == 5)
    // Through the debounced path too (what CatalogSave.save schedules).
    note = "debounced run"
    CatalogBackupService.scheduleSnapshot(from: ctx)
    await settle()
    check("a debounced fits-only snapshot also replaces the newest", files().count == 5
          && files().first.flatMap(myRepoNote) == "debounced run")
    CatalogBackupService.myReposSource = { _, _ in [] }
}

try await run()
try? FileManager.default.removeItem(at: backups)
exit(failures == 0 ? 0 : 1)
