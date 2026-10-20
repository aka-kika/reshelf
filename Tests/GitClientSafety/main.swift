import Foundation

// GitClient safety: no credential prompts, a plain error for a login request,
// and a time limit that really stops a stuck command. Fake "git" scripts and
// real git in a temp folder. Nothing here touches ~/reshelf or the network.

setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
setenv("GIT_CONFIG_NOSYSTEM", "1", 1)

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("reshelf-gitclient-safety-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

struct TestFailure: Error, CustomStringConvertible { let description: String }

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw TestFailure(description: message) }
}

/// An executable shell script standing in for /usr/bin/git.
func script(_ name: String, _ body: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
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

await check("a: git runs with prompts off, the rest of the environment kept, no stdin") {
    setenv("RESHELF_TEST_KEEP", "kept", 1)
    let fake = try script("env-git", """
        printf 'TP=%s AP=[%s] ASKSET=%s KEEP=%s ' "$GIT_TERMINAL_PROMPT" "$GIT_ASKPASS" "${GIT_ASKPASS+yes}" "$RESHELF_TEST_KEEP"
        if read line; then echo "stdin=data"; else echo "stdin=eof"; fi
        """)
    let output = try await GitClient(executableURL: fake).run(arguments: ["var"]).standardOutput
    try expect(output.trimmingCharacters(in: .whitespacesAndNewlines)
               == "TP=0 AP=[] ASKSET=yes KEEP=kept stdin=eof", "got: \(output)")
}

await check("b: real git asked for a username fails fast with the plain login error") {
    // Real git, fed a credential request for a host nobody answers for: with
    // prompts on it would wait on the terminal; here it must fail at once.
    let fake = try script("cred-git", """
        printf 'protocol=https\\nhost=example.invalid\\n\\n' | exec /usr/bin/git "$@"
        """)
    let start = Date()
    do {
        _ = try await GitClient(executableURL: fake)
            .run(arguments: ["-c", "credential.helper=", "credential", "fill"], timeout: 20)
        throw TestFailure(description: "credential fill went through")
    } catch GitClientError.loginRequired {
        try expect(Date().timeIntervalSince(start) < 10, "took too long")
        try expect(GitClientError.loginRequired.localizedDescription.contains("private"), "message")
    }
}

await check("c: a command that hangs is stopped at its time limit") {
    let fake = try script("hang-git", "exec sleep 30")
    let start = Date()
    do {
        _ = try await GitClient(executableURL: fake).run(arguments: ["ls-remote", "origin", "HEAD"], timeout: 1)
        throw TestFailure(description: "hanging command returned")
    } catch let GitClientError.timedOut(arguments, seconds) {
        let elapsed = Date().timeIntervalSince(start)
        try expect(elapsed < 5, "took \(elapsed)s")
        try expect(seconds == 1 && arguments.first == "ls-remote", "error fields")
        let message = GitClientError.timedOut(arguments: ["-c", "filter.lfs.smudge=", "fetch", "origin"], seconds: 600)
            .localizedDescription
        try expect(message.hasPrefix("git fetch got no answer within 600 seconds"), "message: \(message)")
    }
}

await check("d: a child still holding git's output open does not block the timeout") {
    // The shell dies on SIGTERM; its background sleep keeps the pipes open.
    let fake = try script("child-git", "sleep 20 &\nsleep 20")
    let start = Date()
    do {
        _ = try await GitClient(executableURL: fake).run(arguments: ["fetch"], timeout: 1)
        throw TestFailure(description: "hanging command returned")
    } catch GitClientError.timedOut {
        let elapsed = Date().timeIntervalSince(start)
        try expect(elapsed < 8, "took \(elapsed)s")
    }
}

await check("e: a command that ignores SIGTERM is killed") {
    let fake = try script("stubborn-git", "trap '' TERM\nexec sleep 30")
    let start = Date()
    do {
        _ = try await GitClient(executableURL: fake).run(arguments: ["ls-remote"], timeout: 1)
        throw TestFailure(description: "hanging command returned")
    } catch GitClientError.timedOut {
        let elapsed = Date().timeIntervalSince(start)
        try expect(elapsed < 10, "took \(elapsed)s")
    }
}

await check("f: a fast command with a time limit is not affected") {
    let result = try await GitClient().run(arguments: ["--version"], timeout: 30)
    try expect(result.standardOutput.hasPrefix("git version"), "output: \(result.standardOutput)")
}

await check("g: an ordinary failure stays commandFailed") {
    do {
        _ = try await GitClient().run(arguments: ["rev-parse", "--verify", "HEAD"], workingDirectory: root,
                                      timeout: 30)
        throw TestFailure(description: "rev-parse outside a repo went through")
    } catch GitClientError.commandFailed {
        return
    }
}

if failures > 0 {
    print("\(failures) case(s) failed")
    exit(1)
}
