import Foundation

// Logic tests for GitClient.syncToUpstream (the "Pull" path). Each case builds
// throwaway repos with real git in a temp folder: an "upstream" repo and a plain
// clone of it. Nothing here touches ~/reshelf.

// Keep Kika's global git config and hooks out of the test repos.
setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
setenv("GIT_CONFIG_NOSYSTEM", "1", 1)
for key in ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"] { setenv(key, "Test", 1) }
for key in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"] { setenv(key, "test@example.invalid", 1) }

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-gitclient-pull-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

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

var commitCounter = 0
@discardableResult
func commit(_ dir: URL, _ message: String) throws -> String {
    commitCounter += 1
    try "\(message) \(commitCounter)\n".write(to: dir.appendingPathComponent("file-\(commitCounter).txt"),
                                              atomically: true, encoding: .utf8)
    try git(["add", "."], in: dir)
    try git(["commit", "-q", "-m", message], in: dir)
    return try git(["rev-parse", "HEAD"], in: dir)
}

/// A fresh upstream with two commits on `main`, and a plain clone of it.
func makePair(_ name: String) throws -> (upstream: URL, clone: URL) {
    let upstream = root.appendingPathComponent("\(name)-upstream")
    let clone = root.appendingPathComponent("\(name)-clone")
    try FileManager.default.createDirectory(at: upstream, withIntermediateDirectories: true)
    try git(["init", "-q", "-b", "main"], in: upstream)
    try commit(upstream, "first")
    try commit(upstream, "second")
    try git(["clone", "-q", upstream.path, clone.path], in: root)
    return (upstream, clone)
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

/// Sync must refuse with `.localChangesPresent`.
func expectRefused(_ clone: URL) async throws {
    do {
        try await GitClient().syncToUpstream(repositoryURL: clone)
        throw TestFailure(description: "sync went through; expected localChangesPresent")
    } catch GitClientError.localChangesPresent {
        return
    }
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

await check("a: clean clone behind upstream moves to the upstream tip") {
    let (upstream, clone) = try makePair("a")
    let tip = try commit(upstream, "third")
    try await GitClient().syncToUpstream(repositoryURL: clone)
    try expect(try git(["rev-parse", "HEAD"], in: clone) == tip, "HEAD is not the upstream tip")
    try expect(try git(["symbolic-ref", "--short", "HEAD"], in: clone) == "main", "not on main")
}

await check("b: local commit on the default branch is refused and kept") {
    let (upstream, clone) = try makePair("b")
    let local = try commit(clone, "local work")
    try commit(upstream, "third")
    try await expectRefused(clone)
    try expect(try git(["rev-parse", "refs/heads/main"], in: clone) == local, "local commit lost")
}

await check("c: local commit that is also tagged locally is refused and kept") {
    let (upstream, clone) = try makePair("c")
    let local = try commit(clone, "local work")
    try git(["tag", "my-local-tag"], in: clone)
    try git(["tag", "-a", "-m", "annotated", "my-annotated-tag"], in: clone)
    try commit(upstream, "third")
    try await expectRefused(clone)
    try expect(try git(["rev-parse", "refs/heads/main"], in: clone) == local, "local commit lost")
}

await check("d: clone detached on an upstream tag off every branch still syncs") {
    let (upstream, _) = try makePair("d0")
    // Release commit reachable only from tag v1.0 (its branch is deleted).
    try git(["checkout", "-q", "-b", "release"], in: upstream)
    try commit(upstream, "release only")
    try git(["tag", "-a", "-m", "v1.0", "v1.0"], in: upstream)
    try git(["checkout", "-q", "main"], in: upstream)
    try git(["branch", "-q", "-D", "release"], in: upstream)
    let clone = root.appendingPathComponent("d-clone")
    try git(["clone", "-q", upstream.path, clone.path], in: root)
    try git(["checkout", "-q", "--detach", "v1.0"], in: clone)
    // A local-only tag on an upstream commit must not get in the way either.
    try git(["tag", "bookmark", "HEAD~1"], in: clone)
    let tip = try commit(upstream, "third")
    try await GitClient().syncToUpstream(repositoryURL: clone)
    try expect(try git(["rev-parse", "HEAD"], in: clone) == tip, "HEAD is not the upstream tip")
}

await check("e: upstream force-push with a plain reference clone still syncs") {
    let (upstream, clone) = try makePair("e")
    try git(["reset", "-q", "--hard", "HEAD~1"], in: upstream)
    let tip = try commit(upstream, "rewritten second")
    try await GitClient().syncToUpstream(repositoryURL: clone)
    try expect(try git(["rev-parse", "HEAD"], in: clone) == tip, "HEAD is not the rewritten tip")
}

await check("e1c5: a clone on another upstream branch syncs that branch and stays on it") {
    let (upstream, clone) = try makePair("f")
    try git(["checkout", "-q", "-b", "feature"], in: upstream)
    try commit(upstream, "feature one")
    try git(["checkout", "-q", "main"], in: upstream)
    try git(["fetch", "-q", "origin"], in: clone)
    try git(["checkout", "-q", "-b", "feature", "--track", "origin/feature"], in: clone)
    try git(["checkout", "-q", "feature"], in: upstream)
    let featureTip = try commit(upstream, "feature two")
    try git(["checkout", "-q", "main"], in: upstream)
    let mainTip = try commit(upstream, "main three")
    let remote = try await GitClient().remoteTipForCheckout(repositoryURL: clone)
    try expect(remote == featureTip, "update check compares with \(remote ?? "nil"), not the feature tip")
    try await GitClient().syncToUpstream(repositoryURL: clone)
    try expect(try git(["symbolic-ref", "--short", "HEAD"], in: clone) == "feature", "Pull switched branch")
    try expect(try git(["rev-parse", "HEAD"], in: clone) == featureTip, "HEAD is not the feature tip")
    let after = try await GitClient().remoteTipForCheckout(repositoryURL: clone)
    try expect(after == (try git(["rev-parse", "HEAD"], in: clone)), "still shows updates after Pull")
    try expect(mainTip != featureTip, "setup")
}

await check("e1c5: a detached clone still compares with the default branch") {
    let (upstream, clone) = try makePair("g")
    try git(["checkout", "-q", "--detach", "HEAD"], in: clone)
    let tip = try commit(upstream, "third")
    let remote = try await GitClient().remoteTipForCheckout(repositoryURL: clone)
    try expect(remote == tip, "detached clone not compared with main")
}

await check("e1c5: a refused sync does not re-point a tag the user moved") {
    let (upstream, clone) = try makePair("h")
    try git(["tag", "v1", "HEAD~1"], in: upstream)
    try git(["fetch", "-q", "--tags", "origin"], in: clone)
    let local = try commit(clone, "local work")
    try git(["tag", "-f", "v1", local], in: clone)
    try commit(upstream, "third")
    try await expectRefused(clone)
    try expect(try git(["rev-parse", "refs/tags/v1"], in: clone) == local, "the user's tag was re-pointed")
}

if failures > 0 {
    print("\(failures) case(s) failed")
    exit(1)
}
