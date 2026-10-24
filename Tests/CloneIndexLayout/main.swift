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

func markClone(_ dir: URL) throws {
    try "reshelf\n".write(to: CatalogCloneService.cloneMarkerURL(for: dir), atomically: true, encoding: .utf8)
}

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
for made in [aiTool, fallback, packed, detached] { try markClone(made) }
let unmarked = try finishedClone("Projects/mine", slug: "kika/mine")
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

await check("9ca4: a finished checkout without the marker is not a clone") {
    try expect(CloneLocation.isCustom, "test root is not a custom folder")
    let index = CatalogCloneService.scanCloneIndex(root: root)
    try expect(index["kika/mine"] == nil, "unmarked checkout adopted")
    try expect(!CatalogCloneService.hasCloneMarker(unmarked), "scan stamped a custom folder")
    let mine = try project("https://github.com/kika/mine", category: "Projects")
    try expect(!CatalogCloneService.isCloned(mine), "unmarked checkout shows Cloned")
    let fallbackName = root.appendingPathComponent("Projects/kika-mine")
    try expect(same(CatalogCloneService.destination(for: mine), fallbackName),
               "destination is the user's own checkout")
    do {
        try CatalogCloneService.removeClone(mine)
        throw TestFailure(description: "removeClone returned quietly")
    } catch let error as CatalogCloneService.CloneError {
        guard case .notCloned = error else { throw TestFailure(description: "got \(error)") }
    }
    try expect(fm.fileExists(atPath: unmarked.appendingPathComponent(".git").path),
               "Remove Local Clone touched the unmarked checkout")
}

await check("9ca4: the default-folder stamp marks layout clones only") {
    let legacyRoot = base.appendingPathComponent("legacy-root")
    let old = legacyRoot.appendingPathComponent("Utility/oldtool")
    try fm.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try git(["clone", "-q", upstream.path, old.path], in: base)
    try git(["remote", "set-url", "origin", "https://github.com/kika/oldtool.git"], in: old)
    let otherName = legacyRoot.appendingPathComponent("work/my-copy")
    try fm.createDirectory(at: otherName.deletingLastPathComponent(), withIntermediateDirectories: true)
    try git(["clone", "-q", upstream.path, otherName.path], in: base)
    try git(["remote", "set-url", "origin", "https://github.com/kika/third.git"], in: otherName)
    try expect(CatalogCloneService.scanCloneIndex(root: legacyRoot)["kika/oldtool"] == nil,
               "unstamped legacy clone adopted before the stamp")
    try expect(CatalogCloneService.stampLegacyCloneMarkers(root: legacyRoot) == 1, "stamp count")
    try expect(CatalogCloneService.hasCloneMarker(old), "layout clone not marked")
    try expect(!CatalogCloneService.hasCloneMarker(otherName), "other name was marked")
    try expect(same(CatalogCloneService.scanCloneIndex(root: legacyRoot)["kika/oldtool"], old),
               "stamped clone not adopted")
}

await check("90ef: a file where the clone would go is not deleted") {
    let blocked = try project("https://github.com/kika/plainfile", category: "Utility")
    let first = root.appendingPathComponent("Utility/plainfile")
    let file = root.appendingPathComponent("Utility/kika-plainfile")
    try fm.createDirectory(at: first, withIntermediateDirectories: true)
    try "occupied\n".write(to: first.appendingPathComponent("readme"), atomically: true, encoding: .utf8)
    try "not a repo\n".write(to: file, atomically: true, encoding: .utf8)
    try expect(same(CatalogCloneService.destination(for: blocked), file),
               "destination is not the file in the way")
    do {
        _ = try await CatalogCloneService.clone(blocked)
        throw TestFailure(description: "clone replaced the file")
    } catch let error as CatalogCloneService.CloneError {
        guard case .folderInUse = error else { throw TestFailure(description: "got \(error)") }
    }
    let text = try String(contentsOf: file, encoding: .utf8)
    try expect(text == "not a repo\n", "the file was deleted or changed: \(text)")
}

await check("3393: a custom clone folder is not rearranged by the category merge") {
    let kept = root.appendingPathComponent("Coding Agents/my-work/note.txt")
    try fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "keep\n".write(to: kept, atomically: true, encoding: .utf8)
    let moved = CatalogCloneService.mergeCategoryFolders(["Coding Agents": "AI / Agent"])
    try expect(moved == 0, "custom folder moved \(moved) entries")
    try expect(fm.fileExists(atPath: kept.path), "a non-clone folder was moved")
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

await check("5689: the origin remote decides the clone, not the first github.com") {
    let config = """
    [core]
        comment = see github.com/other/decoy
    [remote "upstream"]
        url = https://github.com/decoy/repo.git
    [remote "origin"]
        url = git@github.com:Kika/Real.git
    """
    try expect(CatalogCloneService.originSlug(fromConfig: config) == "kika/real",
               "got \(CatalogCloneService.originSlug(fromConfig: config) ?? "nil")")
    let noOrigin = """
    [remote "upstream"]
        url = https://github.com/decoy/repo.git
    """
    try expect(CatalogCloneService.originSlug(fromConfig: noOrigin) == nil, "a non-origin remote was used")
}

await check("deec: an unborn branch is not trashed as a half-written clone") {
    let unborn = root.appendingPathComponent("Utility/unborn")
    try fm.createDirectory(at: unborn, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"], in: unborn)
    try git(["remote", "add", "origin", "https://github.com/kika/unborn.git"], in: unborn)
    try expect(!CatalogCloneService.isFinishedCheckout(unborn), "unborn counted as finished")
    try expect(!CatalogCloneService.isAbortedClone(unborn), "unborn counted as aborted")
    try expect(CatalogCloneService.isAbortedClone(noIndex), "a clone with no index is not aborted")
    let row = try project("https://github.com/kika/unborn", category: "Utility")
    do {
        _ = try await CatalogCloneService.clone(row)
        throw TestFailure(description: "clone replaced the unborn checkout")
    } catch let error as CatalogCloneService.CloneError {
        guard case .folderInUse = error else { throw TestFailure(description: "got \(error)") }
    }
    try expect(fm.fileExists(atPath: unborn.appendingPathComponent(".git").path),
               "the unborn checkout was trashed")
}

await check("b009: the default folder chosen by hand is not a custom folder") {
    let defaultPath = CloneLocation.defaultRootURL.path
    try expect(CloneLocation.isDefault(storedPath: nil), "nil")
    try expect(CloneLocation.isDefault(storedPath: "  "), "blank")
    try expect(CloneLocation.isDefault(storedPath: defaultPath), "default path")
    try expect(CloneLocation.isDefault(storedPath: defaultPath + "/"), "trailing slash")
    try expect(!CloneLocation.isDefault(storedPath: root.path), "custom root counts as default")
    UserDefaults.standard.setVolatileDomain([CloneLocation.storageKey: defaultPath],
                                            forName: UserDefaults.argumentDomain)
    defer {
        UserDefaults.standard.setVolatileDomain([CloneLocation.storageKey: root.path],
                                                forName: UserDefaults.argumentDomain)
    }
    try expect(!CloneLocation.isCustom, "default picked by hand counts as custom")
}

await check("b009: old clones in a custom folder are adopted only at a row's exact layout path") {
    let oldRoot = base.appendingPathComponent("old-custom-root")
    func oldClone(_ path: String, slug: String) throws -> URL {
        let dir = oldRoot.appendingPathComponent(path)
        try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try git(["clone", "-q", upstream.path, dir.path], in: base)
        try git(["remote", "set-url", "origin", "https://github.com/\(slug).git"], in: dir)
        return dir
    }
    let exact = try oldClone("AI Agent/alpha", slug: "kika/alpha")
    let fallbackName = try oldClone("CLI/kika-beta", slug: "kika/beta")
    let otherCategory = try oldClone("Media/gamma", slug: "kika/gamma")
    let notInCatalog = try oldClone("CLI/delta", slug: "kika/delta")
    let wrongOrigin = try oldClone("CLI/epsilon", slug: "someone/else")
    let rows = [
        try project("https://github.com/kika/alpha", category: "AI / Agent"),
        try project("https://github.com/kika/beta", category: "CLI"),
        try project("https://github.com/kika/gamma", category: "CLI"),
        try project("https://github.com/kika/epsilon", category: "CLI"),
    ]
    try expect(CatalogCloneService.adoptLegacyClones(rows, root: oldRoot) == 2, "adopt count")
    try expect(CatalogCloneService.hasCloneMarker(exact), "exact layout clone not adopted")
    try expect(CatalogCloneService.hasCloneMarker(fallbackName), "owner-repo clone not adopted")
    try expect(!CatalogCloneService.hasCloneMarker(otherCategory), "clone in another category adopted")
    try expect(!CatalogCloneService.hasCloneMarker(notInCatalog), "checkout of no row adopted")
    try expect(!CatalogCloneService.hasCloneMarker(wrongOrigin), "checkout of another repo adopted")
    let index = CatalogCloneService.scanCloneIndex(root: oldRoot)
    try expect(same(index["kika/alpha"], exact) && same(index["kika/beta"], fallbackName),
               "adopted clones not in the index")
    try expect(CatalogCloneService.adoptLegacyClones(rows, root: oldRoot) == 0, "second run adopted again")
}

await check("44fc: a clone reshelf started and that died before any objects is replaceable") {
    let started = root.appendingPathComponent("Utility/started")
    try fm.createDirectory(at: started, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"], in: started)
    try git(["remote", "add", "origin", "https://github.com/kika/started.git"], in: started)
    try expect(!CatalogCloneService.isLeftoverClone(started), "an unborn checkout counts as a leftover")
    let note = CatalogCloneService.cloneInProgressURL(for: started)
    try Data().write(to: note)
    try expect(CatalogCloneService.isLeftoverClone(started), "a started clone is not a leftover")
    try expect(CatalogCloneService.scanCloneIndex(root: root)["kika/started"] == nil, "a started clone is indexed")
    try expect(CatalogCloneService.isLeftoverClone(noIndex), "a clone with objects and no index is not a leftover")
    try expect(!CatalogCloneService.isLeftoverClone(aiTool), "a finished clone counts as a leftover")
    try fm.removeItem(at: note)
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
