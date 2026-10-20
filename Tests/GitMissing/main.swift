import Foundation

// Git missing: a fake "git" that exits 1 for everything stands in for the
// Command Line Tools stub. Temp folder only.

setvbuf(stdout, nil, _IONBF, 0)
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-git-missing-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

struct TestFailure: Error, CustomStringConvertible { let description: String }

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

/// An executable shell script standing in for /usr/bin/git. Every
/// `--version` call is counted in <name>.probes.
func script(_ name: String, _ body: String) throws -> (url: URL, probes: URL) {
    let url = root.appendingPathComponent(name)
    let probes = root.appendingPathComponent("\(name).probes")
    try """
        #!/bin/sh
        [ "$1" = "--version" ] && echo probe >> '\(probes.path)'
        \(body)

        """.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, probes)
}

func probeCount(_ probes: URL) -> Int {
    ((try? String(contentsOf: probes, encoding: .utf8)) ?? "").split(separator: "\n").count
}

let plainError = GitClientError.gitMissing.errorDescription ?? ""

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

await check("661c: git that exits 1 gives the plain Command Line Tools error, asked once") {
    try expect(plainError.contains("Command Line Tools") && plainError.contains("xcode-select --install"),
               "message: \(plainError)")
    let fake = try script("stub-git", "echo 'xcrun: error: invalid active developer path' >&2; exit 1")
    let git = GitClient(executableURL: fake.url)
    for arguments in [["clone", "https://github.com/a/b", root.appendingPathComponent("b").path],
                      ["ls-remote", "origin", "HEAD"], ["fetch", "origin"]] {
        do {
            _ = try await git.run(arguments: arguments, workingDirectory: root, timeout: 30)
            throw TestFailure(description: "\(arguments[0]) went through")
        } catch let error as GitClientError {
            guard case .gitMissing = error else { throw TestFailure(description: "got \(error)") }
            try expect(error.localizedDescription == plainError, "shown: \(error.localizedDescription)")
        }
    }
    try expect(probeCount(fake.probes) == 1, "git was asked \(probeCount(fake.probes)) times, not once")
}

await check("661c: through the app's calls (Check, Pull) too") {
    let fake = try script("stub-git-2", "exit 1")
    let git = GitClient(executableURL: fake.url)
    do {
        _ = try await git.remoteDefaultHead(repositoryURL: root)
        throw TestFailure(description: "update check went through")
    } catch GitClientError.gitMissing {}
    do {
        try await git.syncToUpstream(repositoryURL: root)
        throw TestFailure(description: "pull went through")
    } catch GitClientError.gitMissing {}
    try expect(probeCount(fake.probes) == 1, "git was asked \(probeCount(fake.probes)) times, not once")
}

await check("661c: no git at all (nothing at the path) gives the same plain error") {
    let git = GitClient(executableURL: root.appendingPathComponent("no-such-git"))
    do {
        _ = try await git.run(arguments: ["ls-remote", "origin"], workingDirectory: root)
        throw TestFailure(description: "went through")
    } catch GitClientError.gitMissing {}
}

await check("661c: when git works, a failing command keeps git's own error") {
    let fake = try script("working-git", """
        [ "$1" = "--version" ] && { echo 'git version 2.50.0'; exit 0; }
        echo 'fatal: not a git repository' >&2; exit 128
        """)
    let git = GitClient(executableURL: fake.url)
    for _ in 0..<2 {
        do {
            _ = try await git.run(arguments: ["rev-parse", "HEAD"], workingDirectory: root)
            throw TestFailure(description: "went through")
        } catch let GitClientError.commandFailed(_, exitCode, standardError) {
            try expect(exitCode == 128 && standardError.contains("not a git repository"), "got \(standardError)")
        }
    }
    try expect(probeCount(fake.probes) == 1, "a working git was asked \(probeCount(fake.probes)) times")
}

await check("661c: real git is found and works") {
    let output = try await GitClient().run(arguments: ["--version"]).standardOutput
    try expect(output.hasPrefix("git version"), "got: \(output)")
}

if failures > 0 {
    print("\(failures) case(s) failed")
    exit(1)
}
