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

func candidate(_ name: String, top: Bool, _ text: String) -> FitScorer.Candidate {
    FitScorer.Candidate(key: "test/\(name)", name: name, isTopShelf: top, text: text)
}

@MainActor
func run() throws {
    // 1. README cleaning drops code, badges and link targets, keeps labels.
    let readme = """
    # Sift ![badge](https://img.shields.io/x.svg)
    Scores Mac apps. See [the docs](https://example.com/docs).
    ```swift
    let secret = codeThatShouldNotCount()
    ```
    <img src="x.png"> Uninstall with care.
    """
    let clean = FitScorer.cleanReadme(readme)
    check("cleaning keeps prose", clean.contains("Scores Mac apps") && clean.contains("the docs")
          && clean.contains("Uninstall with care"))
    check("cleaning drops code, badges, links and html",
          !clean.contains("codeThatShouldNotCount") && !clean.contains("shields") && !clean.contains("example.com")
          && !clean.contains("img"))

    // 2. Tokens: stop words out, plurals trimmed, hyphen words both ways.
    let toks = FitScorer.tokens("The menu-bar agents and Agent tools")
    check("hyphen word kept whole and split", toks.contains("menubar") && toks.contains("menu") && toks.contains("bar"))
    check("plural meets singular", toks.filter { $0 == "agent" }.count == 2)
    check("stop words out", !toks.contains("the") && !toks.contains("and") && !toks.contains("tool"))

    // 3. Ranking: the repo sharing the project's rare words wins; a repo with
    // one coincidental word does not fit at all.
    let project = "uninstaller that finds leftover preference files caches and launch agents after removing an application bundle"
    let cands = [
        candidate("cleaner", top: false, "uninstaller removes application bundle leftover caches preference files launch agents"),
        candidate("notes", top: true, "markdown notes editor with folders and sync"),
        candidate("weather", top: false, "weather forecast widget"),
        candidate("bundler", top: true, "application bundle tool, finds leftover caches"),
        candidate("oneword", top: false, "a game about caches"),
    ]
    let ordered = FitScorer.ordered(FitScorer.score(project: project, candidates: cands))
    check("best match first", ordered.first?.candidate.name == "cleaner")
    let picked = FitScorer.pick(ordered, hidden: [])
    let names = picked.map(\.candidate.name)
    check("unrelated repos left out", !names.contains("notes") && !names.contains("weather"))
    check("one shared word is not a fit", !names.contains("oneword"))
    check("Top Shelf listed before The Collector", names == ["bundler", "cleaner"])
    check("hidden repos never come back in a pick",
          !FitScorer.pick(ordered, hidden: ["test/cleaner"]).map(\.candidate.name).contains("cleaner"))
    check("nothing fits gives an empty list",
          FitScorer.pick(FitScorer.ordered(FitScorer.score(project: "quantum chemistry lattice",
                                                           candidates: cands)), hidden: []).isEmpty)
    check("fallback why names the shared words", FitScorer.fallbackWhy(ordered[0]).hasPrefix("Shares: "))

    // 4. Top Shelf share: 6 Top Shelf at most while The Collector has more.
    let many = (0..<9).map { candidate("t\($0)", top: true, "uninstaller leftover caches bundle \($0)") }
        + (0..<9).map { candidate("c\($0)", top: false, "uninstaller leftover caches bundle \($0)") }
    let pickedMany = FitScorer.pick(FitScorer.ordered(FitScorer.score(project: project, candidates: many)), hidden: [])
    check("at most 10 fits", pickedMany.count == FitScorer.maxFits)
    check("6 from Top Shelf, then 4 from The Collector",
          pickedMany.prefix(6).allSatisfy(\.candidate.isTopShelf)
          && pickedMany.dropFirst(6).allSatisfy { !$0.candidate.isTopShelf })

    // 5. Merge: hidden stay hidden, new gets the dot, gone ones drop, first run marks nothing.
    let prev = [FitMerge.Row(key: "a", rank: 0, why: "", isNew: false, isHidden: false),
                FitMerge.Row(key: "h", rank: 1, why: "", isNew: false, isHidden: true),
                FitMerge.Row(key: "gone", rank: 2, why: "", isNew: false, isHidden: false)]
    let merged = FitMerge.merge(previous: prev, found: [("h", "x"), ("b", "new one"), ("a", "again")], isFirstRun: false)
    check("hidden repo stays hidden, once", merged.filter { $0.key == "h" }.count == 1
          && merged.first { $0.key == "h" }?.isHidden == true)
    check("new repo marked new", merged.first { $0.key == "b" }?.isNew == true)
    check("known repo not new", merged.first { $0.key == "a" }?.isNew == false)
    check("repo not found again is dropped", !merged.contains { $0.key == "gone" })
    check("first run marks nothing new",
          FitMerge.merge(previous: [], found: [("a", ""), ("b", "")], isFirstRun: true).allSatisfy { !$0.isNew })

    // 6. Saved fits in the store.
    let ctx = try makeContext()
    let shelfRow = ToolProject(name: "Cleaner", githubURL: "https://github.com/Test/Cleaner", status: .topShelf)
    ctx.insert(shelfRow)
    try ctx.save()
    let added = ProjectFitsService.add([("kika/Sift", "https://github.com/kika/Sift", "Scores apps")], in: ctx)
    check("repo added to the sidebar", added.count == 1 && added[0].displayName == "Sift")
    check("adding it again does nothing",
          ProjectFitsService.add([("KIKA/sift", "https://github.com/kika/Sift", "")], in: ctx).isEmpty)
    let sift = added[0]
    ProjectFitsService.applyRun(repoID: sift.id, found: [("test/cleaner", "Finds leftovers")], note: "", in: ctx)
    check("run saved with its time", sift.lastRunAt != nil && sift.previousRunAt == nil)
    check("fit saved", ProjectFitsService.fits(for: sift.id, in: ctx).map(\.repoKey) == ["test/cleaner"])
    ProjectFitsService.setHidden(true, repoKey: "test/cleaner", repoID: sift.id, in: ctx)
    ProjectFitsService.applyRun(repoID: sift.id, found: [("test/cleaner", "again"), ("test/other", "new")],
                                note: "", in: ctx)
    let after = ProjectFitsService.fits(for: sift.id, in: ctx)
    check("hidden fit survives the next run hidden", after.first { $0.repoKey == "test/cleaner" }?.isHidden == true)
    check("second run remembers the first", sift.previousRunAt != nil)
    check("new fit after a re-run has the dot", after.first { $0.repoKey == "test/other" }?.isNew == true)

    // 7. Backups carry My Repos; an old file without them still reads.
    CatalogBackupService.myReposSource = { context in
        if let context { ProjectFitsService.refreshSnapshot(in: context) }
        return ProjectFitsService.latestSnapshot
    }
    let projects = (try? ctx.fetch(FetchDescriptor<ToolProject>())) ?? []
    check("backup written", CatalogBackupService.writeSnapshot(projects, reason: "Before a test"))
    guard let file = CatalogBackupService.snapshotURLs().first,
          let data = try? Data(contentsOf: file) else { check("backup file", false); return }
    let rows = (try? CatalogExportService.decodeMyRepos(data)) ?? []
    check("backup has the repo and both fits", rows.count == 1 && rows[0].fits.count == 2)
    check("fit row names the shelf repo", rows[0].fits.first { $0.repo == "test/cleaner" }?.name == "Cleaner"
          && rows[0].fits.first { $0.repo == "test/cleaner" }?.shelf == "topShelf")
    let old = Data(#"{"exportedAt":"2026-01-01T00:00:00Z","app":"reshelf","version":1,"projectCount":0,"projects":[]}"#.utf8)
    check("file from before Project fits reads", ((try? CatalogExportService.decodeMyRepos(old)) ?? [MyRepoDTO(
        fullName: "x", githubURL: "", summary: "", addedAt: Date(), sortIndex: 0, lastRunNote: "", fits: [])]).isEmpty)

    // 8. Restore into another store adds the repo with its fits; an existing repo keeps its own list.
    let ctx2 = try makeContext()
    check("merge adds the missing repo", ProjectFitsService.merge(rows, in: ctx2) == 1)
    let restored = ProjectFitsService.repos(in: ctx2)
    check("restored repo has its fits and hidden one",
          restored.count == 1 && ProjectFitsService.fits(for: restored[0].id, in: ctx2).filter(\.isHidden).count == 1)
    check("merge again adds nothing", ProjectFitsService.merge(rows, in: ctx2) == 0)

    // 9. Remove from Sidebar removes the fits, never the shelf repo.
    ProjectFitsService.remove(sift, in: ctx)
    check("repo and fits gone", ProjectFitsService.repos(in: ctx).isEmpty
          && ((try? ctx.fetch(FetchDescriptor<RepoFit>())) ?? []).isEmpty)
    check("shelf repo untouched", ((try? ctx.fetch(FetchDescriptor<ToolProject>())) ?? []).count == 1)
}

MainActor.assumeIsolated {
    do { try run() } catch { check("setup: \(error)", false) }
}
try? FileManager.default.removeItem(at: backups)
exit(failures == 0 ? 0 : 1)
