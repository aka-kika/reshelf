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
    check("best fit first, whichever shelf (round 2)", names == ["cleaner", "bundler"])
    check("hidden repos never come back in a pick",
          !FitScorer.pick(ordered, hidden: ["test/cleaner"]).map(\.candidate.name).contains("cleaner"))
    check("nothing fits gives an empty list",
          FitScorer.pick(FitScorer.ordered(FitScorer.score(project: "quantum chemistry lattice",
                                                           candidates: cands)), hidden: []).isEmpty)
    check("fallback why names the shared words", FitScorer.fallbackWhy(ordered[0]).hasPrefix("Shares: "))

    // 4. Round 2: no fixed slots. At most the limit; an equal fit goes to
    //    Top Shelf; a better Collector fit beats a weaker Top Shelf one.
    let many = (0..<20).map { candidate("t\($0)", top: true, "uninstaller leftover caches bundle \($0)") }
        + (0..<20).map { candidate("c\($0)", top: false, "uninstaller leftover caches bundle \($0)") }
    let scoredMany = FitScorer.score(project: project, candidates: many)
    check("default limit is 15", FitScorer.pick(scoredMany, hidden: []).count == 15)
    check("limit 25 keeps 25", FitScorer.pick(scoredMany, hidden: [], limit: 25).count == 25)
    check("equal fits: Top Shelf first",
          FitScorer.pick(scoredMany, hidden: [], limit: 20).allSatisfy(\.candidate.isTopShelf))
    let weakTop = [candidate("weak-top", top: true, "uninstaller caches and a lot of unrelated words about weather maps music"),
                   candidate("strong-collector", top: false, "uninstaller leftover caches preference files launch agents bundle")]
    check("a better Collector fit beats a weaker Top Shelf one",
          FitScorer.pick(FitScorer.score(project: project, candidates: weakTop + cands), hidden: [])
            .first?.candidate.name == "strong-collector")
    check("shortlist follows the limit", FitScorer.shortlistCount(for: 10) == 20
          && FitScorer.shortlistCount(for: 25) == 35)

    // 4b. A shelf repo that fits many of her repos is pushed down, so the
    //     one specific to this project wins (round 2: imark, cortex in 5 of 11).
    let pushProject = "markdown image library tags folders alt text photos"
    let others = ["markdown editor with folders", "markdown editor for agents", "markdown library browser", "wiki"]
    let push = [candidate("generic-md", top: false, "markdown notes editor library tags folders"),
                candidate("photos", top: false, "image library photos tags alt text")]
    let without = FitScorer.ordered(FitScorer.score(project: pushProject, candidates: push + cands))
    let with = FitScorer.ordered(FitScorer.score(project: pushProject, others: others, candidates: push + cands))
    let generic = with.first { $0.candidate.name == "generic-md" }
    check("generic repo counts how many of her repos it fits", (generic?.breadth ?? 0) >= 2)
    check("generic repo scores lower with her other repos known",
          (generic?.score ?? 1) < (without.first { $0.candidate.name == "generic-md" }?.score ?? 0))
    check("the specific repo comes first", with.first?.candidate.name == "photos")

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

    // 5b. New Fits: only repos added or changed since the last run,
    //     merged into the saved list by score.
    let lastRun = Date(timeIntervalSince1970: 1_000_000)
    let changed = FitIncremental.changed([
        ("old", lastRun.addingTimeInterval(-100), nil),
        ("added", lastRun.addingTimeInterval(100), nil),
        ("pushed", lastRun.addingTimeInterval(-100), lastRun.addingTimeInterval(50)),
        ("stale", lastRun.addingTimeInterval(-100), lastRun.addingTimeInterval(-10)),
    ], since: lastRun)
    check("new and changed repos found, the rest left alone", changed == ["added", "pushed"])
    let savedList = [FitIncremental.Saved(key: "a", why: "a why", score: 0.20, isTopShelf: false),
                     FitIncremental.Saved(key: "pushed", why: "old why", score: 0.30, isTopShelf: false),
                     FitIncremental.Saved(key: "gone", why: "", score: 0.25, isTopShelf: true),
                     FitIncremental.Saved(key: "c", why: "c why", score: 0.10, isTopShelf: false)]
    let newList = [FitIncremental.Saved(key: "added", why: "", score: 0.15, isTopShelf: true),
                   FitIncremental.Saved(key: "tie", why: "", score: 0.10, isTopShelf: true)]
    let mergedRun = FitIncremental.merge(saved: savedList, new: newList, changed: ["added", "pushed", "tie"],
                                         onShelf: ["a", "pushed", "c", "added", "tie"], limit: 3)
    check("new fits slot in by score; changed and gone ones re-checked or dropped; limit kept",
          mergedRun.map(\.key) == ["a", "added", "tie"])
    check("tie goes to Top Shelf", FitIncremental.merge(saved: savedList, new: newList, changed: [],
                                                       onShelf: ["c"], limit: 5).map(\.key) == ["added", "tie", "c"])
    check("run signature names version and limit",
          FitScorer.runSignature(limit: 15) != FitScorer.runSignature(limit: 20))

    // 5c. Settings > Fits filters.
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let monthsAgo = { (m: Int) in Calendar(identifier: .gregorian).date(byAdding: .month, value: -m, to: now)! }
    var f = FitFilters()
    check("no filter lets everything through",
          f.allows(projectLanguage: "Swift", language: "", isArchived: true, license: "AGPL-3.0", updated: nil, now: now)
          && !f.isActive && f.signature.isEmpty)
    f.sameLanguage = true
    check("same language: match passes, ignoring case",
          f.allows(projectLanguage: "Swift", language: "swift", isArchived: false, license: "", updated: nil, now: now))
    check("same language: other or unknown language left out",
          !f.allows(projectLanguage: "Swift", language: "Rust", isArchived: false, license: "", updated: nil, now: now)
          && !f.allows(projectLanguage: "Swift", language: "", isArchived: false, license: "", updated: nil, now: now))
    check("same language: her repo has none, nothing to compare",
          f.allows(projectLanguage: "", language: "Rust", isArchived: false, license: "", updated: nil, now: now))
    f = FitFilters(hideStrongCopyleft: true)
    check("GPL and AGPL hidden, LGPL and MIT kept",
          !f.allows(projectLanguage: "", language: "", isArchived: false, license: "GPL-3.0", updated: nil, now: now)
          && !f.allows(projectLanguage: "", language: "", isArchived: false, license: "AGPL-3.0", updated: nil, now: now)
          && f.allows(projectLanguage: "", language: "", isArchived: false, license: "LGPL-3.0", updated: nil, now: now)
          && f.allows(projectLanguage: "", language: "", isArchived: false, license: "MIT", updated: nil, now: now))
    f = FitFilters(hideArchived: true)
    check("archived hidden", !f.allows(projectLanguage: "", language: "", isArchived: true, license: "", updated: nil, now: now))
    f = FitFilters(updated: .sixMonths)
    check("updated in the last 6 months: 5 months ago passes, 7 and unknown do not",
          f.allows(projectLanguage: "", language: "", isArchived: false, license: "", updated: monthsAgo(5), now: now)
          && !f.allows(projectLanguage: "", language: "", isArchived: false, license: "", updated: monthsAgo(7), now: now)
          && !f.allows(projectLanguage: "", language: "", isArchived: false, license: "", updated: nil, now: now))
    check("stored facts fill in: licence and push date",
          !FitFilters(updated: .threeMonths).allows(projectLanguage: "", facts: RepoFacts(pushedAt: monthsAgo(4)),
                                                    license: "", lastUpdated: nil, now: now)
          && !FitFilters(hideStrongCopyleft: true).allows(projectLanguage: "", facts: RepoFacts(license: "GPL-2.0"),
                                                          license: "", lastUpdated: nil, now: now))
    check("a filter changes the run signature",
          FitScorer.runSignature(limit: 15, filters: FitFilters(hideArchived: true).signature)
          != FitScorer.runSignature(limit: 15))
    let suite = UserDefaults(suiteName: "reshelf-fits-test-\(UUID().uuidString)")!
    suite.set(true, forKey: FitFilters.sameLanguageKey)
    suite.set("lastYear", forKey: FitFilters.updatedKey)
    check("filters read from settings", FitFilters.current(suite) == FitFilters(sameLanguage: true, updated: .lastYear))

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
    ProjectFitsService.applyRun(repoID: sift.id, found: [("test/cleaner", "Finds leftovers")],
                                scores: ["test/cleaner": 0.12], matchText: "sift text",
                                signature: FitScorer.runSignature(limit: 15), note: "", in: ctx)
    check("run saved with its time", sift.lastRunAt != nil && sift.previousRunAt == nil)
    check("score, match text and signature saved", ProjectFitsService.fits(for: sift.id, in: ctx).first?.score == 0.12
          && sift.matchText == "sift text" && sift.runSignature == FitScorer.runSignature(limit: 15))
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
    check("backup carries the score", rows[0].fits.first { $0.repo == "test/cleaner" }?.score == 0.12)
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
