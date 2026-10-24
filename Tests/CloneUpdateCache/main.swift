import Foundation
import SwiftData

// Update-check cache, Remove Local Clone with nothing to remove, and the
// clone-folder helpers. A local "upstream" repo is cloned into a fake clone
// root with origin set to github.com/kika/tool; `url.<upstream>.insteadOf`
// sends git back to the local repo, so ls-remote, fetch and pull run offline.

setvbuf(stdout, nil, _IONBF, 0)
setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
for key in ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"] { setenv(key, "Test", 1) }
for key in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"] { setenv(key, "test@example.invalid", 1) }

let fm = FileManager.default
let base = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-update-cache-\(UUID().uuidString)")
let root = base.appendingPathComponent("clone-root")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }

// Volatile argument domain: never written to disk, read before saved prefs.
UserDefaults.standard.setVolatileDomain([CloneLocation.storageKey: root.path],
                                        forName: UserDefaults.argumentDomain)

struct TestFailure: Error, CustomStringConvertible { let description: String }

@discardableResult
func git(_ arguments: [String], in dir: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = dir
    let out = Pipe()
    process.standardOutput = out
    process.standardError = Pipe()
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw TestFailure(description: "git \(arguments.joined(separator: " ")) failed")
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

var failures = 0
@MainActor
func check(_ name: String, _ body: () async throws -> Void) async {
    do {
        try await body()
        print("PASS \(name)")
    } catch {
        failures += 1
        print("FAIL \(name): \(error)")
    }
}

var containers: [ModelContainer] = []
@MainActor
func project(_ url: String, category: String) throws -> ToolProject {
    let container = try ModelContainer(for: ToolProject.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    containers.append(container)
    let project = ToolProject(name: "test", githubURL: url, category: category)
    container.mainContext.insert(project)
    return project
}

let upstream = base.appendingPathComponent("upstream")
try fm.createDirectory(at: upstream, withIntermediateDirectories: true)
try git(["init", "-q", "-b", "main"], in: upstream)
try "hello\n".write(to: upstream.appendingPathComponent("README"), atomically: true, encoding: .utf8)
try git(["add", "."], in: upstream)
try git(["commit", "-q", "-m", "first"], in: upstream)

let clone = root.appendingPathComponent("Utility/tool")
try fm.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
try git(["clone", "-q", upstream.path, clone.path], in: base)
try git(["remote", "set-url", "origin", "https://github.com/kika/tool.git"], in: clone)
try git(["config", "url.\(upstream.path).insteadOf", "https://github.com/kika/tool.git"], in: clone)
try "reshelf\n".write(to: CatalogCloneService.cloneMarkerURL(for: clone), atomically: true, encoding: .utf8)

await check("7514: a check is remembered and reused; Check and Pull replace it") {
    let tool = try project("https://github.com/kika/tool", category: "Utility")
    try expect(CatalogCloneService.isCloned(tool), "test clone not found")
    try expect(CatalogCloneService.cachedUpdateStatus(for: tool.id) == nil, "cache not empty at start")

    try expect(await CatalogCloneService.updateStatus(for: tool) == .upToDate, "first check not up to date")
    try expect(CatalogCloneService.cachedUpdateStatus(for: tool.id) == .upToDate, "first check not remembered")

    // Upstream moves on. Reselecting reads the cache (no ls-remote), so it
    // still says what the last check found.
    try "more\n".write(to: upstream.appendingPathComponent("README"), atomically: true, encoding: .utf8)
    try git(["commit", "-q", "-am", "second"], in: upstream)
    try expect(CatalogCloneService.cachedUpdateStatus(for: tool.id) == .upToDate, "cache changed without a check")

    // An explicit Check (or a sweep, which calls the same function) replaces it.
    try expect(await CatalogCloneService.updateStatus(for: tool) == .updatesAvailable, "behind not seen")
    try expect(CatalogCloneService.cachedUpdateStatus(for: tool.id) == .updatesAvailable, "newer check not remembered")

    try await CatalogCloneService.pull(tool)
    try expect(CatalogCloneService.cachedUpdateStatus(for: tool.id) == .upToDate, "pull didn't update the cache")
    try expect(try git(["rev-parse", "HEAD"], in: clone) == git(["rev-parse", "HEAD"], in: upstream),
               "pull didn't reach upstream")
}

await check("7514: a status from the list's notification replaces it; errors are not kept") {
    let id = UUID()
    CatalogCloneService.rememberUpdateStatus(.upToDate, for: id)
    CatalogCloneService.rememberUpdateStatus(.updatesAvailable, for: id)
    try expect(CatalogCloneService.cachedUpdateStatus(for: id) == .updatesAvailable, "newer status not kept")
    CatalogCloneService.rememberUpdateStatus(.error("offline"), for: id)
    try expect(CatalogCloneService.cachedUpdateStatus(for: id) == nil, "an error was cached")

    let other = try project("https://github.com/kika/elsewhere", category: "Utility")
    CatalogCloneService.rememberUpdateStatus(.upToDate, for: other.id)
    _ = await CatalogCloneService.updateStatus(for: other) // not cloned: an error
    try expect(CatalogCloneService.cachedUpdateStatus(for: other.id) == nil, "failed check left an old answer")
}

await check("800f: Remove Local Clone with no clone throws, touches nothing") {
    let missing = try project("https://github.com/kika/never-cloned", category: "Utility")
    do {
        try CatalogCloneService.removeClone(missing)
        throw TestFailure(description: "removeClone returned quietly")
    } catch let error as CatalogCloneService.CloneError {
        guard case .notCloned = error else { throw TestFailure(description: "got \(error)") }
        let text = error.localizedDescription
        try expect(text.contains(root.path) && text.contains("nothing was moved"), "message: \(text)")
    }
    try expect(fm.fileExists(atPath: clone.appendingPathComponent(".git").path), "the other clone was touched")
}

await check("800f: clone-folder helpers Settings uses") {
    try expect(CloneLocation.rootURL(forStoredPath: nil) == CloneLocation.defaultRootURL, "nil not default")
    try expect(CloneLocation.rootURL(forStoredPath: "  ") == CloneLocation.defaultRootURL, "blank not default")
    try expect(CloneLocation.rootURL(forStoredPath: root.path).path == root.path, "custom path changed")
    // What the warning counts: clones at reshelf's layout in the old folder.
    try expect(CatalogCloneService.scanCloneIndex(root: root).count == 1, "old folder count")
    let empty = base.appendingPathComponent("new-root")
    try fm.createDirectory(at: empty, withIntermediateDirectories: true)
    try expect(CatalogCloneService.scanCloneIndex(root: empty).isEmpty, "empty folder has clones")
}

if failures > 0 {
    print("\(failures) case(s) failed")
    exit(1)
}
