import Foundation
import SwiftData

// Clone index and half-written clones. Real git repos in a temp folder: a local
// "upstream" repo is cloned into a fake clone root, then origin is pointed at a
// github.com URL (git never contacts it). Nothing here touches ~/reshelf.

setvbuf(stdout, nil, _IONBF, 0)
setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
for key in ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"] { setenv(key, "Test", 1) }
for key in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"] { setenv(key, "test@example.invalid", 1) }

let fm = FileManager.default
let base = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-clone-index-\(UUID().uuidString)")
let root = base.appendingPathComponent("clone-root")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }

// The clone root for CloneLocation.rootURL, in the argument domain: volatile
// (never written to disk) and read before the app's saved preference.
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

let upstream = base.appendingPathComponent("upstream")
try fm.createDirectory(at: upstream, withIntermediateDirectories: true)
try git(["init", "-q", "-b", "main"], in: upstream)
try "hello\n".write(to: upstream.appendingPathComponent("README"), atomically: true, encoding: .utf8)
try git(["add", "."], in: upstream)
try git(["commit", "-q", "-m", "first"], in: upstream)

/// A finished clone at `path` whose origin says github.com/<slug>.
@discardableResult
func finishedClone(_ path: String, slug: String) throws -> URL {
    let dir = root.appendingPathComponent(path)
    try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
    try git(["clone", "-q", upstream.path, dir.path], in: base)
    try git(["remote", "set-url", "origin", "https://github.com/\(slug).git"], in: dir)
    return dir
}

/// What a clone killed right after writing its config leaves: origin set, HEAD
/// pointing at a branch that was never written, no index.
@discardableResult
func partialClone(_ path: String, slug: String) throws -> URL {
    let dir = root.appendingPathComponent(path)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"], in: dir)
    try git(["remote", "add", "origin", "https://github.com/\(slug)"], in: dir)
    return dir
}

/// Same folder, ignoring /var vs /private/var and a trailing slash.
func same(_ a: URL?, _ b: URL) -> Bool {
    a?.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
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

// Layout used by the cases below.
let aiTool = try finishedClone("AI Agent/tool", slug: "kika/tool")
let fallback = try finishedClone("Media/kika-other", slug: "Kika/Other")
let packed = try finishedClone("CLI/packed", slug: "kika/packed")
try git(["pack-refs", "--all"], in: packed)
let detached = try finishedClone("CLI/detached", slug: "kika/detached")
try git(["checkout", "-q", "--detach", "HEAD"], in: detached)
let flat = try finishedClone("myproject", slug: "kika/myproject")
let renamed = try finishedClone("work/my-copy", slug: "kika/third")
let deep = try finishedClone("work/deep/fourth", slug: "kika/fourth")
let partial = try partialClone("Utility/partial", slug: "kika/partial")
let noIndex = try finishedClone("Utility/noindex", slug: "kika/noindex")
try fm.removeItem(at: noIndex.appendingPathComponent(".git/index"))

await check("c31e: clones at <root>/<Category>/<repo> and <owner>-<repo> are adopted") {
    let index = CatalogCloneService.scanCloneIndex(root: root)
    try expect(same(index["kika/tool"], aiTool), "repo-name layout")
    try expect(same(index["kika/other"], fallback), "owner-repo layout")
    try expect(index["kika/packed"] != nil, "packed refs")
    try expect(index["kika/detached"] != nil, "detached HEAD")
}

await check("c31e: checkouts elsewhere under the root are not adopted") {
    let index = CatalogCloneService.scanCloneIndex(root: root)
    try expect(index["kika/myproject"] == nil, "root-level working copy adopted: \(flat.path)")
    try expect(index["kika/third"] == nil, "folder named differently from its repo adopted: \(renamed.path)")
    try expect(index["kika/fourth"] == nil, "deeper checkout adopted: \(deep.path)")
}

await check("a578: a clone that died midway is not counted as cloned") {
    let index = CatalogCloneService.scanCloneIndex(root: root)
    try expect(index["kika/partial"] == nil, "origin-only folder adopted")
    try expect(index["kika/noindex"] == nil, "clone without an index adopted")
    try expect(!CatalogCloneService.isFinishedCheckout(partial), "partial counts as finished")
    try expect(await !GitClient().headResolves(repositoryURL: partial), "partial HEAD resolves")
    try expect(CatalogCloneService.isFinishedCheckout(aiTool), "finished clone not finished")
    try expect(await GitClient().headResolves(repositoryURL: aiTool), "finished HEAD does not resolve")
}

await check("layout names") {
    try expect(CatalogCloneService.isLayoutFolderName("Tool", forSlug: "kika/tool"), "repo, other case")
    try expect(CatalogCloneService.isLayoutFolderName("kika-tool", forSlug: "kika/tool"), "owner-repo")
    try expect(!CatalogCloneService.isLayoutFolderName("tool-fork", forSlug: "kika/tool"), "other name")
    try expect(!CatalogCloneService.isLayoutFolderName("tool", forSlug: "tool"), "bad slug")
}

await check("through the app paths: isCloned / destination / clone() adopt only finished layout clones") {
    guard same(CloneLocation.rootURL, root) else {
        throw TestFailure(description: "test clone root not in effect: \(CloneLocation.rootURL.path)")
    }
    CatalogCloneService.invalidateCloneIndex()
    let tool = try project("https://github.com/kika/tool", category: "AI / Agent")
    try expect(CatalogCloneService.isCloned(tool), "finished clone not cloned")
    let adopted = try await CatalogCloneService.clone(tool)
    try expect(same(adopted, aiTool), "clone() did not return the clone")

    let mine = try project("https://github.com/kika/myproject", category: "")
    try expect(!CatalogCloneService.isCloned(mine), "root-level working copy shows Cloned")

    let half = try project("https://github.com/kika/partial", category: "Utility")
    try expect(!CatalogCloneService.isCloned(half), "partial clone shows Cloned")
    // destination() still points at the partial folder, so clone() replaces
    // it (Trash + fresh clone) instead of cloning beside it.
    try expect(same(CatalogCloneService.destination(for: half), partial),
               "destination is not the partial folder")
}

if failures > 0 {
    print("\(failures) case(s) failed")
    exit(1)
}
