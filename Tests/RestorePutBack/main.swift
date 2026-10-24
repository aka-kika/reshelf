import Foundation
import SwiftData

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

let backups = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: backups)
CatalogBackupService.backupsDirectoryOverride = backups

@MainActor
func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ToolProject.self, CatalogFolder.self, configurations: config)
    return ModelContext(container)
}

@MainActor
func all(_ context: ModelContext) -> [ToolProject] {
    (try? context.fetch(FetchDescriptor<ToolProject>(sortBy: [SortDescriptor(\.name)]))) ?? []
}

@MainActor
func project(_ name: String, _ status: ProjectStatus, tags: [String] = [], notes: String = "") -> ToolProject {
    let p = ToolProject(name: name, githubURL: "https://github.com/test/\(name)", status: status,
                        tags: tags, notes: notes)
    // Sub-second dates, like the live store; the file keeps whole seconds.
    p.addedDate = Date(timeIntervalSince1970: 1_760_000_000.734)
    p.lastCheckedDate = Date(timeIntervalSince1970: 1_760_000_100.25)
    return p
}

@MainActor
func run() throws {
    // 1. Yard Sale move, then undo with put-back.
    let ctx = try makeContext()
    let a = project("alpha", .topShelf, tags: ["swift"], notes: "keep")
    let b = project("beta", .topShelf, tags: ["mcp"])
    let c = project("gamma", .collector)
    [a, b, c].forEach(ctx.insert)
    try ctx.save()

    CatalogBackupService.writeSnapshot(all(ctx), reason: "Before moving 2 repos to Yard Sale")
    guard let before = CatalogBackupService.snapshotURLs().first else {
        check("labelled backup written", false); return
    }
    check("labelled backup written", CatalogBackupService.reason(in: before) == "Before moving 2 repos to Yard Sale")

    let unchangedPlan = CatalogImportService.plan(rows: CatalogBackupService.projects(in: before),
                                                  sourceURL: before, context: ctx)
    check("unchanged catalog: nothing counts as changed (dates round to seconds)",
          CatalogImportService.changedMatches(in: unchangedPlan, context: ctx).isEmpty)

    a.status = .yardSale
    b.status = .yardSale
    b.tags = []
    try ctx.save()

    let additive = CatalogBackupService.restore(from: before, puttingBackChanges: false,
                                                into: ctx, snapshotDate: "test")
    check("restore without put-back changes nothing", additive.added == 0 && additive.updated == 0
          && a.status == .yardSale)

    let undo = CatalogBackupService.restore(from: before, puttingBackChanges: true,
                                            into: ctx, snapshotDate: "test")
    check("put-back updates exactly the 2 changed repos", undo.updated == 2 && undo.added == 0)
    check("shelves and tags are back", a.status == .topShelf && b.status == .topShelf && b.tags == ["mcp"]
          && a.notes == "keep" && c.status == .collector)
    check("restore wrote its own labelled backup first",
          CatalogBackupService.snapshotURLs().contains {
              CatalogBackupService.reason(in: $0) == "Before restoring the backup from test"
          })

    // 2. A deleted repo comes back and a changed one is put back in one go.
    CatalogBackupService.writeSnapshot(all(ctx), reason: "Before removing gamma")
    let snap2 = CatalogBackupService.snapshotURLs().first!
    ctx.delete(c)
    a.notes = "edited"
    try ctx.save()
    let both = CatalogBackupService.restore(from: snap2, puttingBackChanges: true, into: ctx, snapshotDate: "t2")
    check("deleted repo added back and changed repo put back", both.added == 1 && both.updated == 1
          && all(ctx).count == 3 && a.notes == "keep")

    // 3. Folders: a repo moved into a folder after the backup leaves it again.
    let folder = CatalogFolderService.create(name: "Photos app", in: ctx)!
    b.folderID = folder.id
    try ctx.save()
    CatalogBackupService.writeSnapshot(all(ctx), folders: CatalogFolderService.folders(in: ctx),
                                       reason: "Before folder change")
    let snap3 = CatalogBackupService.snapshotURLs().first!
    a.folderID = folder.id
    b.folderID = nil
    try ctx.save()
    let folders = CatalogBackupService.restore(from: snap3, puttingBackChanges: true, into: ctx, snapshotDate: "t3")
    check("folder membership put back both ways", folders.updated == 2 && a.folderID == nil && b.folderID == folder.id)

    // 4. Routine (unlabelled) snapshots still skip identical content; labelled ones don't.
    let countBefore = CatalogBackupService.snapshotURLs().count
    CatalogBackupService.writeSnapshot(all(ctx), folders: CatalogFolderService.folders(in: ctx))
    let afterRoutine = CatalogBackupService.snapshotURLs().count
    CatalogBackupService.writeSnapshot(all(ctx), folders: CatalogFolderService.folders(in: ctx))
    check("routine snapshot of unchanged catalog is skipped",
          CatalogBackupService.snapshotURLs().count == afterRoutine && afterRoutine <= countBefore + 1)
    CatalogBackupService.writeSnapshot(all(ctx), folders: CatalogFolderService.folders(in: ctx), reason: "Before x")
    check("labelled snapshot is always written", CatalogBackupService.snapshotURLs().count == afterRoutine + 1)

    // 5. Emptying the shelf on purpose sticks; an empty catalog at launch still restores.
    let ctx2 = try makeContext()
    CatalogBackupService.clearEmptiedByUser()
    check("empty catalog at launch restores the newest backup",
          CatalogBackupService.restoreIfCatalogEmpty(context: ctx2) && !all(ctx2).isEmpty)
    let ctx3 = try makeContext()
    CatalogBackupService.noteProjectCount(old: 0, new: 0)
    check("launch with 0 rows does not count as emptied", !CatalogBackupService.emptiedByUser)
    CatalogBackupService.noteProjectCount(old: 3, new: 0)
    check("deleting the last repo is remembered", CatalogBackupService.emptiedByUser)
    check("an emptied shelf is not refilled from a backup",
          !CatalogBackupService.restoreIfCatalogEmpty(context: ctx3) && all(ctx3).isEmpty)
    CatalogBackupService.noteProjectCount(old: 0, new: 1)
    check("adding a repo clears it", !CatalogBackupService.emptiedByUser)
    CatalogBackupService.clearEmptiedByUser()

    // 6. Remove Duplicate Repos merge.
    let keeper = project("dup", .topShelf, tags: ["Swift", "ui"], notes: "short")
    keeper.useCases = ["menus"]
    let victim = project("dup", .collector, tags: ["swift", "mcp"], notes: "a much longer note about why")
    victim.useCases = ["menus", "agents"]
    victim.personalNote = "saved for the menu bar"
    victim.websiteURL = "https://example.com"
    DuplicateMerge.merge(from: victim, into: keeper)
    check("tags joined without case duplicates", keeper.tags == ["Swift", "ui", "mcp"])
    check("use cases joined", keeper.useCases == ["menus", "agents"])
    check("both notes kept", keeper.notes == "short\n\na much longer note about why")
    check("empty fields filled", keeper.personalNote == "saved for the menu bar" && keeper.websiteURL == "https://example.com")
    check("contained note not repeated", DuplicateMerge.joined("one two three", "two") == "one two three")
    check("shelf of kept copy unchanged", keeper.status == .topShelf)

    // 7. Put-back restores shelf, tags and notes, and leaves name, link,
    //    description and category alone (76e9).
    let ctx4 = try makeContext()
    let row = project("delta", .topShelf, tags: ["swift"], notes: "n")
    row.category = "CLI"
    row.shortDescription = "original"
    row.personalNote = "why"
    ctx4.insert(row)
    try ctx4.save()
    CatalogBackupService.writeSnapshot(all(ctx4), reason: "Before the rename")
    guard let snapName = CatalogBackupService.snapshotURLs().first(where: {
        CatalogBackupService.reason(in: $0) == "Before the rename"
    }) else {
        check("rename backup written", false)
        return
    }
    row.name = "delta renamed"
    row.category = "Games"
    row.shortDescription = "changed"
    row.status = .yardSale
    row.tags = []
    row.notes = "edited"
    row.personalNote = ""
    try ctx4.save()
    let back = CatalogBackupService.restore(from: snapName, puttingBackChanges: true,
                                            into: ctx4, snapshotDate: "rename")
    check("put-back counts the shelf and note change", back.updated == 1)
    check("shelf, tags and notes are back",
          row.status == .topShelf && row.tags == ["swift"] && row.notes == "n" && row.personalNote == "why")
    // 8. A restore that changes nothing does not bring back a deleted folder (0163).
    let ctx5 = try makeContext()
    let epsilon = project("epsilon", .collector)
    ctx5.insert(epsilon)
    let gone = CatalogFolderService.create(name: "Gone", in: ctx5)!
    epsilon.folderID = gone.id
    try ctx5.save()
    CatalogBackupService.writeSnapshot(all(ctx5), folders: CatalogFolderService.folders(in: ctx5),
                                       reason: "Before deleting folder Gone")
    guard let snapGone = CatalogBackupService.snapshotURLs().first(where: {
        CatalogBackupService.reason(in: $0) == "Before deleting folder Gone"
    }) else {
        check("gone-folder backup written", false)
        return
    }
    check("deleting the folder ungroups", CatalogFolderService.delete(gone, in: ctx5) == 1)
    let quiet = CatalogBackupService.restore(from: snapGone, puttingBackChanges: false,
                                             into: ctx5, snapshotDate: "gone")
    check("nothing to restore when the repo is still there", quiet.added == 0 && quiet.updated == 0)
    check("a deleted folder stays deleted",
          !CatalogFolderService.folders(in: ctx5).contains { $0.name == "Gone" })

    check("name, link, description and category stay",
          row.name == "delta renamed" && row.category == "Games"
          && row.githubURL == "https://github.com/test/delta" && row.shortDescription == "changed")
}

MainActor.assumeIsolated {
    do { try run() } catch { check("setup: \(error)", false) }
}
try? FileManager.default.removeItem(at: backups)
exit(failures == 0 ? 0 : 1)
