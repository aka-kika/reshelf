import Foundation
import SwiftData

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: work)
try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let backups = work.appendingPathComponent("backups")
CatalogBackupService.backupsDirectoryOverride = backups
FitsInbox.fileOverride = work.appendingPathComponent("fits-inbox.jsonl")

@MainActor
func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ToolProject.self, CatalogFolder.self, MyRepo.self, RepoFit.self,
                                       configurations: config)
    return ModelContext(container)
}

func write(_ lines: [String]) {
    try! (lines.joined(separator: "\n") + "\n").write(to: FitsInbox.fileURL, atomically: true, encoding: .utf8)
}

func labelledBackups() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasSuffix("-before.json") }
}

@MainActor
func run() throws {
    let ctx = try makeContext()
    ctx.insert(ToolProject(name: "Mantis", githubURL: "https://github.com/guoyingtao/Mantis"))
    let kartina = MyRepo(fullName: "kika/Kartina", githubURL: "https://github.com/kika/Kartina")
    let mcpock = MyRepo(fullName: "kika/mcpock", githubURL: "https://github.com/kika/mcpock", sortIndex: 1)
    ctx.insert(kartina)
    ctx.insert(mcpock)
    let mantis = RepoFit(myRepoID: kartina.id, repoKey: "guoyingtao/mantis", rank: 0, why: "", isNew: true, isHidden: false)
    let shelf = RepoFit(myRepoID: kartina.id, repoKey: "ssamsenpai/shelf", rank: 1, why: "", isNew: false, isHidden: false)
    let also = RepoFit(myRepoID: kartina.id, repoKey: "x/also", rank: 2, why: "", isNew: false, isHidden: false)
    let mcpMantis = RepoFit(myRepoID: mcpock.id, repoKey: "guoyingtao/mantis", rank: 0, why: "", isNew: false, isHidden: false)
    let switchA = RepoFit(myRepoID: mcpock.id, repoKey: "a/claude-mcp-switch", rank: 1, why: "", isNew: false, isHidden: false)
    for fit in [mantis, shelf, also, mcpMantis, switchA] { ctx.insert(fit) }
    try ctx.save()

    // 1. Parse keeps hide lines only.
    let parsed = FitsInbox.parse("""
        {"myRepo":"kika/Kartina","repo":"guoyingtao/mantis","action":"hide"}
        not json
        {"myRepo":"","repo":"x/also"}
        {"myRepo":"kika/Kartina","repo":"x/also","action":"show"}

        {"myRepo":"kika/Kartina","repo":"x/also"}
        """)
    check("parse keeps the hide lines (no action means hide)", parsed.count == 2 && parsed[1].repo == "x/also")

    // 2. Drain: her repo by owner/name and the fit by its key, any case, link
    //    or owner/name; only that repo's fit; a labelled backup first.
    write([#"{"myRepo":"KIKA/kartina","repo":"GuoYingTao/Mantis","action":"hide","name":"Mantis"}"#,
           #"{"myRepo":"kika/Kartina","repo":"https://github.com/x/also.git","action":"hide"}"#,
           #"{"myRepo":"kika/Kartina","repo":"x/also","action":"hide"}"#,
           #"{"myRepo":"kika/Kartina","repo":"x/no-longer-a-fit","action":"hide"}"#,
           #"{"myRepo":"kika/Localpen","repo":"x/also","action":"hide"}"#])
    let hid = FitsInbox.drain(in: ctx)
    check("two fits hidden", hid == 2)
    check("the app's own hidden flag is set", mantis.isHidden && also.isHidden)
    check("New stays as the app's Hide leaves it", mantis.isNew)
    check("other fits and other repos' fits untouched", !shelf.isHidden && !mcpMantis.isHidden && !switchA.isHidden)
    check("a labelled backup came first", labelledBackups().count == 1)
    check("the backup carries the fits", ProjectFitsService.latestSnapshot.first { $0.fullName == "kika/Kartina" }?
        .fits.first { $0.repo == "guoyingtao/mantis" }?.isHidden == true)
    let left = (try? String(contentsOf: FitsInbox.fileURL, encoding: .utf8)) ?? ""
    check("a line for a repo not under My Repos stays", left.contains("Localpen") && !left.contains("mantis")
          && !left.contains("no-longer-a-fit"))
    let reading = (try? FileManager.default.contentsOfDirectory(atPath: work.path))?.filter { $0.hasSuffix(".reading") } ?? []
    check("nothing left being read", reading.isEmpty)

    // 3. Again: nothing to hide, no new backup; once the repo is added it applies.
    check("second drain hides nothing", FitsInbox.drain(in: ctx) == 0 && labelledBackups().count == 1)
    let localpen = MyRepo(fullName: "kika/Localpen", githubURL: "https://github.com/kika/Localpen", sortIndex: 2)
    ctx.insert(localpen)
    let lpAlso = RepoFit(myRepoID: localpen.id, repoKey: "x/also", rank: 0, why: "", isNew: false, isHidden: false)
    ctx.insert(lpAlso)
    try ctx.save()
    check("line applied once the repo is under My Repos", FitsInbox.drain(in: ctx) == 1 && lpAlso.isHidden)
    check("inbox gone when all applied", !FileManager.default.fileExists(atPath: FitsInbox.fileURL.path))

    // 4. A failed save keeps the lines for next time and the fits shown.
    write([#"{"myRepo":"kika/mcpock","repo":"a/claude-mcp-switch","action":"hide"}"#])
    shelf.why = "an unsaved edit of hers"
    CatalogSave.failureForTesting = NSError(domain: "test", code: 1)
    check("failed save hides nothing", FitsInbox.drain(in: ctx) == 0 && !switchA.isHidden)
    check("a failed save leaves her other edits", shelf.why == "an unsaved edit of hers")
    CatalogSave.failureForTesting = nil
    check("kept lines apply on the next drain", FitsInbox.drain(in: ctx) == 1 && switchA.isHidden)

    // 5. A leftover .reading file (a crash mid-drain) is read.
    let tail = work.appendingPathComponent("fits-inbox.tail.reading")
    try (#"{"myRepo":"kika/mcpock","repo":"guoyingtao/mantis","action":"hide"}"# + "\n")
        .write(to: tail, atomically: true, encoding: .utf8)
    check("a leftover .reading file is read", FitsInbox.drain(in: ctx) == 1 && mcpMantis.isHidden
          && !FileManager.default.fileExists(atPath: tail.path))

    // 6. Show in the app undoes it, and a later run keeps it hidden until then.
    ProjectFitsService.setHidden(false, repoKey: "guoyingtao/mantis", repoID: kartina.id, in: ctx)
    check("the app's Show brings it back", !mantis.isHidden)
}

MainActor.assumeIsolated {
    do { try run() } catch { check("setup: \(error)", false) }
}
try? FileManager.default.removeItem(at: work)
exit(failures == 0 ? 0 : 1)
