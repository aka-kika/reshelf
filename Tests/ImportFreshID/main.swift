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
    (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
}

@MainActor
func idsUnique(_ context: ModelContext) -> Bool {
    let ids = all(context).map(\.id)
    return Set(ids).count == ids.count
}

@MainActor
func run() throws {
    // 1. Restore after editing a repo's GitHub URL: the backup row no longer
    //    matches by URL, so it is added, and must not reuse the live id.
    let ctx = try makeContext()
    let a = ToolProject(name: "alpha", githubURL: "https://github.com/test/alpha")
    let b = ToolProject(name: "beta", githubURL: "https://github.com/test/beta")
    [a, b].forEach(ctx.insert)
    try ctx.save()
    let aID = a.id
    let backup = try CatalogExportService.decode(CatalogExportService.encode(all(ctx)))

    a.githubURL = "https://github.com/test/alpha-renamed"
    try ctx.save()

    let result = CatalogImportService.restore(backup, folders: [], puttingBackChanges: true,
                                              into: ctx, backupReason: "test")
    check("restore adds the old-URL row", result.added == 1 && all(ctx).count == 3)
    check("no two rows share an id after restore", idsUnique(ctx))
    check("the live row keeps its id", all(ctx).contains { $0.id == aID && $0.githubURL.hasSuffix("alpha-renamed") })
    check("the restored row got a fresh id",
          all(ctx).first { $0.githubURL == "https://github.com/test/alpha" }.map { $0.id != aID } ?? false)

    // 2. Import (additive merge) with the same clash.
    let ctx2 = try makeContext()
    let c = ToolProject(name: "gamma", githubURL: "https://github.com/test/gamma")
    ctx2.insert(c)
    try ctx2.save()
    var row = try CatalogExportService.decode(CatalogExportService.encode([c]))[0]
    row.githubURL = "https://github.com/test/other"
    let added = CatalogImportService.merge([row], into: ctx2)
    check("import adds the clashing row", added == 1 && all(ctx2).count == 2)
    check("no two rows share an id after import", idsUnique(ctx2))

    // 3. Two rows in one file with the same id and different repos.
    let ctx3 = try makeContext()
    var r1 = row
    r1.githubURL = "https://github.com/test/one"
    var r2 = row
    r2.githubURL = "https://github.com/test/two"
    let added3 = CatalogImportService.merge([r1, r2], into: ctx3)
    check("both same-id rows are added", added3 == 2 && all(ctx3).count == 2)
    check("they end up with different ids", idsUnique(ctx3))
    check("the first keeps the file's id", all(ctx3).contains { $0.id.uuidString == row.id })

    // 4. No clash: the file's id is kept (restore into an empty catalog).
    let ctx4 = try makeContext()
    CatalogImportService.merge(backup, into: ctx4)
    check("ids kept when nothing clashes",
          Set(all(ctx4).map(\.id.uuidString)) == Set(backup.map(\.id)))
}

MainActor.assumeIsolated {
    do { try run() } catch { check("setup: \(error)", false) }
}
try? FileManager.default.removeItem(at: backups)
if failures > 0 { print("\(failures) failed"); exit(1) }
print("ImportFreshID: all passed")
