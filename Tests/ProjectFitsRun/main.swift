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
    let container = try ModelContainer(for: ToolProject.self, CatalogFolder.self, MyRepo.self, RepoFit.self,
                                       configurations: config)
    return ModelContext(container)
}

@MainActor
func run() async throws {
    // 1. Her repo list: forks and archived ones left out; a user name is
    //    needed without a token, and an odd one is refused before any call.
    FakeGitHub.pages["/users/kika/repos?type=owner&sort=pushed&per_page=100&page=1"] = .body("""
    [{"full_name":"kika/Sift","description":"Scores Mac apps","html_url":"https://github.com/kika/Sift","private":false,"fork":false,"archived":false,"pushed_at":"2026-11-01T00:00:00Z","topics":["macos"]},
     {"full_name":"kika/forked","description":null,"html_url":"https://github.com/kika/forked","private":false,"fork":true,"archived":false,"pushed_at":null,"topics":[]},
     {"full_name":"kika/old","description":null,"html_url":"https://github.com/kika/old","private":false,"fork":false,"archived":true,"pushed_at":null}]
    """)
    let mine = try await ProjectFitsGitHub.ownRepos(user: "kika", useToken: false)
    check("own repos without forks and archived", mine.map(\.fullName) == ["kika/Sift"])
    check("private flag read", mine.first?.isPrivate == false)
    var refused = false
    do { _ = try await ProjectFitsGitHub.ownRepos(user: "../etc", useToken: false) } catch { refused = true }
    check("odd user name refused", refused)

    // 2. A shelf, with her own repo and a Yard Sale repo on it.
    let ctx = try makeContext()
    let rows = [
        ToolProject(name: "Mole", shortDescription: "Clean and uninstall Mac apps, find leftover files",
                    githubURL: "https://github.com/tw93/Mole", status: .topShelf),
        ToolProject(name: "uninstally", shortDescription: "Native uninstaller that removes app leftovers",
                    githubURL: "https://github.com/x/uninstally", status: .collector),
        ToolProject(name: "notes", shortDescription: "Markdown notes", githubURL: "https://github.com/x/notes",
                    status: .topShelf),
        ToolProject(name: "gone", shortDescription: "Uninstall leftovers cleaner app remover",
                    githubURL: "https://github.com/x/gone", status: .yardSale),
        ToolProject(name: "Sift", shortDescription: "Scores Mac apps and uninstalls leftovers",
                    githubURL: "https://github.com/kika/Sift", status: .collector),
    ]
    rows.forEach(ctx.insert)
    try ctx.save()
    let inputs = ProjectFitsRunner.candidateInputs(in: ctx, excluding: "kika/sift")
    let keys = Set(inputs.map(\.key))
    check("Yard Sale left out", !keys.contains("x/gone"))
    check("her own repo left out", !keys.contains("kika/sift"))
    check("Top Shelf and Collector in", keys == ["tw93/mole", "x/uninstally", "x/notes"])

    // 3. A run: her README live, shelf READMEs live for the shortlist.
    FakeGitHub.pages["/repos/kika/sift/readme"] = .body("""
    # Sift
    Uninstall Mac apps cleanly: finds leftover preference files, caches and launch agents.
    """)
    FakeGitHub.pages["/repos/tw93/mole/readme"] = .body("Mole cleans caches and leftover preference files of removed apps.")
    FakeGitHub.pages["/repos/x/uninstally/readme"] = .rateLimited
    var steps: [String] = []
    let outcome = try await ProjectFitsRunner.findFits(fullName: "kika/Sift", summary: "Scores Mac apps",
                                                       inputs: inputs, hidden: []) { steps.append($0.step) }
    let found = outcome.fits.map(\.key)
    check("fits found, unrelated left out", found.contains("tw93/mole") && !found.contains("x/notes"))
    check("every fit has a score", outcome.fits.allSatisfy { (outcome.scores[$0.key] ?? 0) > 0 })
    check("her text kept for other runs", outcome.projectText.contains("leftover preference files"))
    check("every fit has a why line", outcome.fits.allSatisfy { !$0.why.isEmpty })
    check("rate limit is said, saved info used", outcome.note.contains("limit"))
    check("progress reported", steps.contains("Reading READMEs"))
    check("her README was read", FakeGitHub.requested.contains("/repos/kika/sift/readme"))

    // 3b. Her other repos: a README not read before is read once and handed
    //     back to save; a failed read is not saved (asked again next run).
    FakeGitHub.pages["/repos/kika/kartina/readme"] = .body("Image library with tags")
    FakeGitHub.pages["/repos/kika/mcpock/readme"] = .rateLimited
    let otherA = UUID(), otherB = UUID(), otherC = UUID()
    let withOthers = try await ProjectFitsRunner.findFits(
        fullName: "kika/Sift", summary: "", inputs: inputs, hidden: [],
        others: [.init(id: otherA, fullName: "kika/Kartina", text: "Kartina", needsReadme: true),
                 .init(id: otherB, fullName: "kika/mcpock", text: "mcpock", needsReadme: true),
                 .init(id: otherC, fullName: "kika/Localpen", text: "saved text", needsReadme: false)],
        limit: 10) { _ in }
    check("other repo's README read and handed back", withOthers.otherTexts[otherA]?.contains("Image library") == true)
    check("failed read not saved", withOthers.otherTexts[otherB] == nil)
    check("saved text not read again", withOthers.otherTexts[otherC] == nil
          && !FakeGitHub.requested.contains("/repos/kika/localpen/readme"))

    // 4. Hidden ones are never picked again.
    let again = try await ProjectFitsRunner.findFits(fullName: "kika/Sift", summary: "", inputs: inputs,
                                                     hidden: ["tw93/mole"]) { _ in }
    check("hidden fit not picked", !again.fits.map(\.key).contains("tw93/mole"))

    // 5. A repo with nothing to match says so.
    FakeGitHub.pages["/repos/kika/empty/readme"] = .notFound
    var said = ""
    do {
        _ = try await ProjectFitsRunner.findFits(fullName: "kika/empty", summary: "", inputs: inputs,
                                                 hidden: []) { _ in }
    } catch { said = error.localizedDescription }
    check("no README and no description: says so", said.contains("no README"))

    // 6. The whole run through the shared runner saves the list with its time.
    let added = ProjectFitsService.add([("kika/Sift", "https://github.com/kika/Sift", "Scores Mac apps")], in: ctx)
    await ProjectFitsRunner.shared.run(added[0].id, in: ctx)
    check("run saved", added[0].lastRunAt != nil
          && ProjectFitsService.fits(for: added[0].id, in: ctx).contains { $0.repoKey == "tw93/mole" })
    check("runner idle afterwards", !ProjectFitsRunner.shared.isRunning(added[0].id))

    // 7. The list for one of her repos: Top Shelf heading first, new dot,
    //    hidden left out but counted, search narrows, a shelf move regroups.
    let sift = added[0]
    ProjectFitsService.applyRun(repoID: sift.id, found: [("x/uninstally", "removes leftovers"),
                                                         ("tw93/mole", "cleans caches"),
                                                         ("x/notes", "notes")], note: "", in: ctx)
    ProjectFitsService.setHidden(true, repoKey: "x/notes", repoID: sift.id, in: ctx)
    let all = (try? ctx.fetch(FetchDescriptor<ToolProject>())) ?? []
    let fitsNow = (try? ctx.fetch(FetchDescriptor<RepoFit>())) ?? []
    let model = FitsListModel(repo: sift, fits: fitsNow, allProjects: all, search: "")
    check("list: in run order (best fit first), hidden out", model.projects.map(\.name) == ["uninstally", "Mole"])
    check("list: hidden counted in the footer", model.hiddenCount == 1 && model.footer.contains("1 hidden"))
    check("list: new since the run before marked", model.newIDs.count == 1
          && model.newIDs.contains(all.first { $0.name == "uninstally" }!.id))
    check("list: subtitle says how many and when", model.subtitle.hasPrefix("2 fits · last run"))
    let searched = FitsListModel(repo: sift, fits: fitsNow, allProjects: all, search: "native")
    check("list: search narrows the fits", searched.projects.map(\.name) == ["uninstally"])
    all.first { $0.name == "uninstally" }!.status = .topShelf
    let moved = FitsListModel(repo: sift, fits: fitsNow, allProjects: all, search: "")
    check("list: a shelf move keeps the fit order", moved.projects.map(\.name) == ["uninstally", "Mole"])

    // 8. A clone's README on disk is read (README.md, any case).
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fits-readme-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "hello from disk".write(to: dir.appendingPathComponent("Readme.md"), atomically: true, encoding: .utf8)
    check("clone README read from disk", ProjectFitsGitHub.readmeOnDisk(at: dir) == "hello from disk")
    try? FileManager.default.removeItem(at: dir)
}

let done = DispatchSemaphore(value: 0)
Task { @MainActor in
    do { try await run() } catch { check("setup: \(error)", false) }
    done.signal()
}
while done.wait(timeout: .now()) == .timedOut {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
try? FileManager.default.removeItem(at: backups)
exit(failures == 0 ? 0 : 1)
