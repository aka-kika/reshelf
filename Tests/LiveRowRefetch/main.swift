import Foundation
import SwiftData

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL"): \(name)")
    if !ok { failures += 1 }
}

// Real clones without a network: a local "upstream" at <base>/gh/acme/one, and a
// git config that rewrites https://github.com/ to that folder. The clone root is
// a temp folder too (volatile, never written to disk). Nothing here touches ~/reshelf.
let fm = FileManager.default
let base = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-live-row-\(UUID().uuidString)")
let cloneRoot = base.appendingPathComponent("clone-root")
let upstream = base.appendingPathComponent("gh/acme/one")
try fm.createDirectory(at: cloneRoot, withIntermediateDirectories: true)
try fm.createDirectory(at: upstream, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }
let gitConfig = base.appendingPathComponent("gitconfig")
try "[url \"file://\(base.path)/gh/\"]\n\tinsteadOf = https://github.com/\n"
    .write(to: gitConfig, atomically: true, encoding: .utf8)
setenv("GIT_CONFIG_GLOBAL", gitConfig.path, 1)
setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
for key in ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"] { setenv(key, "Test", 1) }
for key in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"] { setenv(key, "test@example.invalid", 1) }
UserDefaults.standard.setVolatileDomain([CloneLocation.storageKey: cloneRoot.path],
                                        forName: UserDefaults.argumentDomain)

func git(_ arguments: [String], in dir: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = dir
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        print("FAIL: setup git \(arguments.joined(separator: " "))")
        exit(1)
    }
}
try git(["init", "-q", "-b", "main"], in: upstream)
try "hello\n".write(to: upstream.appendingPathComponent("README"), atomically: true, encoding: .utf8)
try git(["add", "."], in: upstream)
try git(["commit", "-q", "-m", "first"], in: upstream)

/// Held for the whole run: a context whose container was released traps on its
/// next use, and -O may release a local container after its last mention.
var containers: [ModelContainer] = []

@MainActor
func makeContainer() throws -> ModelContainer {
    let container = try ModelContainer(for: ToolProject.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    containers.append(container)
    return container
}

/// The shape every fixed site follows: capture the id, await, re-fetch, write
/// only to a live row. Returns whether it wrote.
@MainActor
func writeAfterAwait(_ id: UUID, context: ModelContext, during: @MainActor () async -> Void) async -> Bool {
    await during()
    guard let live = LiveProject.fetch(id, in: context) else { return false }
    live.notes = "written after await"
    try? context.save()
    return true
}

@MainActor
func runAll() async throws {
    // 1. A live row is found and the write lands.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "alive")
        context.insert(project)
        try context.save()
        let id = project.id
        let wrote = await writeAfterAwait(id, context: context) { await Task.yield() }
        let reread = LiveProject.fetch(id, in: context)
        check("live row is re-fetched and written", wrote && reread?.notes == "written after await")
        check("isAlive is true for a saved row", LiveProject.isAlive(project))
    }

    // 2. Row deleted and saved during the await: no fetch, no write, no crash.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "gone")
        context.insert(project)
        try context.save()
        let id = project.id
        let wrote = await writeAfterAwait(id, context: context) {
            context.delete(project)
            try? context.save()
        }
        check("row deleted + saved during await: write skipped", !wrote)
        check("row deleted + saved: re-fetch is nil", LiveProject.fetch(id, in: context) == nil)
        check("row deleted + saved: isAlive is false", !LiveProject.isAlive(project))
        let count = (try? context.fetchCount(FetchDescriptor<ToolProject>())) ?? -1
        check("row deleted + saved: store stays empty", count == 0)
    }

    // 3. Row deleted but not saved yet (the delete is still pending).
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "pending")
        context.insert(project)
        try context.save()
        let id = project.id
        context.delete(project)
        check("row deleted, not saved: re-fetch is nil", LiveProject.fetch(id, in: context) == nil)
        check("row deleted, not saved: isAlive is false", !LiveProject.isAlive(project))
    }

    // 4. Row deleted from another context (e.g. a restore) during the await.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "other context")
        context.insert(project)
        try context.save()
        let id = project.id
        let wrote = await writeAfterAwait(id, context: context) {
            let other = ModelContext(container)
            var descriptor = FetchDescriptor<ToolProject>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let row = try? other.fetch(descriptor).first {
                other.delete(row)
                try? other.save()
            }
        }
        check("row deleted from another context: write skipped", !wrote)
    }

    // 5. Refresh-style result list: only rows still alive come back.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let rows = (0..<3).map { ToolProject(name: "repo \($0)") }
        rows.forEach { context.insert($0) }
        try context.save()
        let ids = rows.map(\.id)
        await Task.yield()
        context.delete(rows[1])
        try context.save()
        let live = ids.compactMap { LiveProject.fetch($0, in: context) }
        check("result list holds only live rows", live.map(\.name) == ["repo 0", "repo 2"])
    }

    // 6. 18f0: the real CatalogCloneService.clone, with the row deleted while git
    // runs. git's insteadOf maps https://github.com/ to a local folder, so the
    // clone is real but never leaves this Mac.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "while-cloning", githubURL: "https://github.com/acme/one", category: "Utility")
        context.insert(project)
        try context.save()
        let id = project.id
        let name = project.name // what ProjectListView.cloneProject keeps for its status line
        CatalogCloneService.rememberUpdateStatus(.updatesAvailable, for: id)

        var finished = false
        let task = Task { @MainActor () -> URL in
            defer { finished = true }
            return try await CatalogCloneService.clone(project)
        }
        // Let clone() run up to its first await (git is now running), then
        // delete the row, as the user can from the list while it clones.
        await Task.yield()
        check("18f0: the clone is still running when the row goes", !finished)
        context.delete(project)
        try context.save()
        check("18f0: the row is gone mid-clone", LiveProject.fetch(id, in: context) == nil)

        var dest: URL?
        var error: Error?
        do { dest = try await task.value } catch let e { error = e }
        check("18f0: clone finishes without a crash or an error", error == nil && dest != nil)
        if let dest {
            check("18f0: the checkout landed at the layout path",
                  dest.resolvingSymlinksInPath().path
                  == cloneRoot.appendingPathComponent("Utility/one").resolvingSymlinksInPath().path)
            check("18f0: the clone carries reshelf's marker", CatalogCloneService.hasCloneMarker(dest))
            check("18f0: the clone is a finished checkout", CatalogCloneService.isFinishedCheckout(dest))
        }
        // clone() kept the id across the await and used it after the row died.
        check("18f0: the stale update status of the deleted row was dropped",
              CatalogCloneService.cachedUpdateStatus(for: id) == nil)
        check("18f0: the status line copy still has the name", name == "while-cloning")
        check("18f0: nothing was written back to the deleted row", LiveProject.fetch(id, in: context) == nil)
        let count = (try? context.fetchCount(FetchDescriptor<ToolProject>())) ?? -1
        check("18f0: the store stays empty", count == 0)
    }
}

try await runAll()
exit(failures == 0 ? 0 : 1)
