import Foundation
import SwiftData

setvbuf(stdout, nil, _IONBF, 0)
// Saves schedule a backup. Keep it out of ~/reshelf.
let backups = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-import-urls-\(UUID().uuidString)")
CatalogBackupService.backupsDirectoryOverride = backups
defer { try? FileManager.default.removeItem(at: backups) }
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

var containers: [ModelContainer] = []

@MainActor
func makeContext() throws -> ModelContext {
    let container = try ModelContainer(for: ToolProject.self, CatalogFolder.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    containers.append(container)
    return ModelContext(container)
}

@MainActor
func count(_ context: ModelContext) -> Int {
    (try? context.fetchCount(FetchDescriptor<ToolProject>())) ?? -1
}

let links = (1...6).map { "https://github.com/test/repo\($0)" }

func info(for url: String) -> GitHubRepoInfo {
    GitHubRepoInfo(fullName: url.replacingOccurrences(of: "https://github.com/", with: ""))
}

@MainActor
func run() async throws {
    // 1. Rate limit at the 3rd link: stop there, nothing after it is tried.
    do {
        let ctx = try makeContext()
        var calls = 0
        let outcome = await BulkURLImport.run(
            links, existing: [], into: ctx,
            fetch: { url in
                calls += 1
                if calls >= 3 { throw CaptureError.rateLimited(resetText: "in about 42 minutes") }
                return info(for: url)
            },
            pause: 0, shouldStop: { false }, onProgress: { _ in })
        check("rate limit: stops at the first limit answer", outcome.stop == .rateLimit(resetText: "in about 42 minutes"))
        check("rate limit: no later repo is tried", calls == 3)
        check("rate limit: later repos are not listed as failed", outcome.counts.failed.isEmpty)
        check("rate limit: the 2 saved repos stay", outcome.counts.imported == 2 && count(ctx) == 2)
        check("rate limit: stopped at repo 3", outcome.stoppedAt == 2)
        check("rate limit: links from the limited one on are handed back", outcome.remaining == Array(links[2...]))
    }

    // 2. Stop pressed during the 2nd repo: that repo finishes, nothing more.
    do {
        let ctx = try makeContext()
        var calls = 0
        var stop = false
        let outcome = await BulkURLImport.run(
            links, existing: [], into: ctx,
            fetch: { url in
                calls += 1
                if calls == 2 { stop = true }
                return info(for: url)
            },
            pause: 0, shouldStop: { stop }, onProgress: { _ in })
        check("stop: ends by user", outcome.stop == .byUser)
        check("stop: the repo in flight is finished and kept", calls == 2 && count(ctx) == 2)
        check("stop: the rest is handed back", outcome.remaining == Array(links[2...]))
    }

    // 3. A normal run: duplicates skipped, other errors counted, keeps going.
    do {
        let ctx = try makeContext()
        var progress: [Int] = []
        let outcome = await BulkURLImport.run(
            links + ["https://github.com/TEST/repo1/"], existing: ["test/repo2"], into: ctx,
            fetch: { url in
                if url.hasSuffix("repo4") { throw CaptureError.notFound("test/repo4") }
                return info(for: url)
            },
            pause: 0, shouldStop: { false }, onProgress: { progress.append($0.progress) })
        check("full run: finishes", outcome.stop == .none)
        check("full run: the failed link stays for another try",
              outcome.remaining == ["https://github.com/test/repo4"])
        check("full run: 4 imported", outcome.counts.imported == 4 && count(ctx) == 4)
        check("full run: catalog and in-run duplicates skipped", outcome.counts.skipped == 2)
        check("full run: a missing repo fails without stopping the run", outcome.counts.failed == ["test/repo4"])
        check("full run: progress reaches every link", progress.last == 7)
    }

    // 4. The message says where it stopped and what to do.
    let noToken = BulkURLImport.rateLimitMessage(at: 60, of: 200, resetText: "in about 42 minutes", hasToken: false)
    check("message: repo 61 of 200, reset time, token advice",
          noToken.hasPrefix("GitHub's limit was reached at repo 61 of 200; it resets in about 42 minutes.")
          && noToken.contains("Add a token in Settings → Capture, then import the rest"))
    // 5. A labelled backup is written before the first insert (b638).
    do {
        let ctx = try makeContext()
        ctx.insert(ToolProject(name: "already", githubURL: "https://github.com/test/already", status: .collector))
        try ctx.save()
        let outcome = await BulkURLImport.run(
            ["https://github.com/test/fresh"], existing: [], into: ctx,
            fetch: { url in info(for: url) },
            pause: 0, shouldStop: { false }, onProgress: { _ in })
        let labelled = CatalogBackupService.snapshotURLs().filter {
            CatalogBackupService.reason(in: $0) == "Before importing GitHub URLs"
        }
        let names = labelled.first.map { CatalogBackupService.projects(in: $0).map(\.name) } ?? []
        check("import writes one labelled backup", outcome.counts.imported == 1 && labelled.count == 1)
        // Written before the first insert: it holds the old row, not the new one.
        check("labelled backup holds the catalog as it was before the import",
              names == ["already"])
        check("the import itself still landed after the backup", count(ctx) == 2)
    }

    // 5b. The safety backup cannot be written: nothing is imported, every link comes back.
    do {
        let ctx = try makeContext()
        ctx.insert(ToolProject(name: "kept", githubURL: "https://github.com/test/kept", status: .collector))
        try ctx.save()
        CatalogBackupService.waitForWrites()
        let blocker = backups.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        let saved = CatalogBackupService.backupsDirectoryOverride
        CatalogBackupService.backupsDirectoryOverride = blocker
        var fetches = 0
        let outcome = await BulkURLImport.run(
            links, existing: [], into: ctx,
            fetch: { url in fetches += 1; return info(for: url) },
            pause: 0, shouldStop: { false }, onProgress: { _ in })
        CatalogBackupService.backupsDirectoryOverride = saved
        check("backup failure: the run stops with backupFailed", outcome.stop == .backupFailed)
        check("backup failure: no link is fetched", fetches == 0)
        check("backup failure: nothing is imported", outcome.counts.imported == 0 && count(ctx) == 1)
        check("backup failure: every link is handed back", outcome.remaining == links)
        check("backup failure: override is restored", CatalogBackupService.backupsDirectoryOverride == saved)
    }

    // 6. A save that fails stops the run; that repo is not counted (599e).
    do {
        struct DiskFull: Error {}
        let ctx = try makeContext()
        var calls = 0
        let outcome = await BulkURLImport.run(
            Array(links[0..<4]), existing: [], into: ctx,
            fetch: { url in
                calls += 1
                if calls == 2 { CatalogSave.failureForTesting = DiskFull() }
                return info(for: url)
            },
            pause: 0, shouldStop: { false }, onProgress: { _ in })
        CatalogSave.failureForTesting = nil
        check("failed save: the run stops", outcome.stop == .saveFailed && calls == 2)
        check("failed save: only the saved repo counts", outcome.counts.imported == 1)
        check("failed save: the unsaved row is not in the catalog", count(ctx) == 1)
        check("failed save: that link and the rest go back in the box", outcome.remaining == Array(links[1..<4]))
    }

    // 7. Import Catalog says nothing was added when its save fails (599e).
    do {
        struct DiskFull: Error {}
        let source = try makeContext()
        source.insert(ToolProject(name: "from-file", githubURL: "https://github.com/test/from-file", status: .collector))
        let rows = try source.fetch(FetchDescriptor<ToolProject>()).map(CatalogProjectDTO.init)
        let ctx = try makeContext()
        let plan = CatalogImportService.plan(rows: rows, sourceURL: URL(fileURLWithPath: "/tmp/x.json"), context: ctx)
        CatalogSave.failureForTesting = DiskFull()
        let result = CatalogImportService.apply(plan, updatingExisting: false, into: ctx)
        CatalogSave.failureForTesting = nil
        check("import file: a failed save reports it", result.saveFailed && result.added == 0)
        check("import file: the rows are taken back out", count(ctx) == 0)
    }

    let withToken = BulkURLImport.rateLimitMessage(at: 0, of: 5, resetText: nil, hasToken: true)
    check("message: with a token, no token advice", !withToken.contains("Add a token") && withToken.contains("repo 1 of 5"))
}

try await run()
exit(failures == 0 ? 0 : 1)
