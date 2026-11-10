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
CatalogBackupService.backupsDirectoryOverride = work.appendingPathComponent("backups")
UsedInbox.fileOverride = work.appendingPathComponent("used-inbox.jsonl")

@MainActor
func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: ToolProject.self, CatalogFolder.self, MyRepo.self, RepoFit.self,
                                       configurations: config)
    return ModelContext(container)
}

func write(_ lines: [String]) {
    try! (lines.joined(separator: "\n") + "\n").write(to: UsedInbox.fileURL, atomically: true, encoding: .utf8)
}

func fetchAll(_ ctx: ModelContext) -> [ToolProject] {
    (try? ctx.fetch(FetchDescriptor<ToolProject>(sortBy: [SortDescriptor(\.name)]))) ?? []
}

@MainActor
func run() throws {
    let ctx = try makeContext()
    let lotion = ToolProject(name: "lotion", githubURL: "https://github.com/fayazara/Lotion")
    let mark = ToolProject(name: "mark", githubURL: "https://github.com/vinny380/mark.git")
    ctx.insert(lotion)
    ctx.insert(mark)
    try ctx.save()

    // 1. Parse skips broken and empty lines.
    let parsed = UsedInbox.parse("""
        {"repo":"fayazara/lotion","project":"Localpen","what":"folding"}
        not json
        {"repo":"","project":"Localpen"}

        {"repo":"https://github.com/vinny380/mark","project":"Localpen"}
        """)
    check("parse keeps the good lines only", parsed.count == 2 && parsed[0].what == "folding")

    // 2. Drain: matched by GitHub key (any case, URL or owner/name), once per project.
    write([#"{"repo":"FAYAZARA/lotion","project":"Localpen"}"#,
           #"{"repo":"fayazara/lotion","project":"localpen"}"#,
           #"{"repo":"https://github.com/vinny380/mark","project":"Localpen"}"#,
           #"{"repo":"x/not-on-shelf","project":"Localpen"}"#])
    let added = UsedInbox.drain(in: ctx)
    check("two marks added", added == 2)
    check("lotion reshelfed in Localpen once", lotion.usedIn == ["Localpen"])
    check("mark matched through its .git link", mark.isUsed(in: "localpen"))
    let left = (try? String(contentsOf: UsedInbox.fileURL, encoding: .utf8)) ?? ""
    check("a line for a repo not on the shelf stays", left.contains("not-on-shelf") && !left.contains("lotion"))
    let reading = (try? FileManager.default.contentsOfDirectory(atPath: work.path))?.filter { $0.hasSuffix(".reading") } ?? []
    check("nothing left being read", reading.isEmpty)

    // 3. Draining again changes nothing; once the repo is shelved it applies.
    check("second drain adds nothing", UsedInbox.drain(in: ctx) == 0)
    let late = ToolProject(name: "not-on-shelf", githubURL: "https://github.com/x/not-on-shelf")
    ctx.insert(late)
    try ctx.save()
    check("line applied once the repo is on the shelf", UsedInbox.drain(in: ctx) == 1 && late.usedIn == ["Localpen"])
    check("inbox gone when all applied", !FileManager.default.fileExists(atPath: UsedInbox.fileURL.path))

    // 4. A failed save keeps the lines for next time and the marks off.
    write([#"{"repo":"fayazara/lotion","project":"Kartina"}"#])
    CatalogSave.failureForTesting = NSError(domain: "test", code: 1)
    check("failed save applies nothing", UsedInbox.drain(in: ctx) == 0 && !lotion.isUsed(in: "Kartina"))
    CatalogSave.failureForTesting = nil
    check("kept lines apply on the next drain", UsedInbox.drain(in: ctx) == 1 && lotion.isUsed(in: "Kartina"))

    // 5. Backups carry the UI mark and Reshelfed in; older files leave them alone.
    lotion.likesUI = true
    let dto = CatalogProjectDTO(lotion)
    check("export has both", dto.likesUI == true && dto.usedIn == ["Localpen", "Kartina"])
    let rebuilt = dto.makeToolProject()
    check("restore rebuilds both", rebuilt.likesUI && rebuilt.usedIn == ["Localpen", "Kartina"])
    var old = dto
    old.likesUI = nil
    old.usedIn = nil
    let other = ToolProject(name: "lotion", githubURL: lotion.githubURL)
    other.likesUI = true
    other.usedIn = ["Sift"]
    old.apply(to: other)
    check("an older file keeps marks made here", other.likesUI && other.usedIn == ["Sift"])
    var changed = dto
    changed.likesUI = false
    check("put-back sees a UI mark change", changed.putBackDiffers(from: lotion))
    changed.applyPutBack(to: other)
    check("put-back restores the marks", !other.likesUI && other.usedIn == ["Localpen", "Kartina"])
    let data = try JSONEncoder().encode([dto])
    let json = String(decoding: data, as: UTF8.self)
    check("JSON keys", json.contains("\"likesUI\":true") && json.contains("\"usedIn\""))
    let legacy = try JSONDecoder().decode(CatalogProjectDTO.self, from: Data("""
        {"id":"\(UUID().uuidString)","name":"x","shortDescription":"","longDescription":"","githubURL":"",
         "websiteURL":"","category":"","status":"collector","license":"","stars":"","tags":[],"useCases":[],
         "notes":"","fitScore":0,"addedDate":0,"isLocalFirst":false,"isSelfHosted":false}
        """.utf8))
    check("an older backup still reads", legacy.likesUI == nil && legacy.makeToolProject().usedIn.isEmpty)

    // 6. Remove Duplicate Repos keeps both marks.
    let keeper = ToolProject(name: "dup", githubURL: "https://github.com/a/dup")
    keeper.usedIn = ["Localpen"]
    let victim = ToolProject(name: "dup", githubURL: "https://github.com/a/dup")
    victim.likesUI = true
    victim.usedIn = ["localpen", "Sift"]
    DuplicateMerge.merge(from: victim, into: keeper)
    check("merge keeps the UI mark and joins projects", keeper.likesUI && keeper.usedIn == ["Localpen", "Sift"])
}

MainActor.assumeIsolated {
    do { try run() } catch { check("setup: \(error)", false) }
}
try? FileManager.default.removeItem(at: work)
exit(failures == 0 ? 0 : 1)
