import Foundation

struct GitCommandResult: Equatable {
    let standardOutput: String
    let standardError: String
}

final class GitProcessRegistry {
    static let shared = GitProcessRegistry()

    private let lock = NSLock()
    private var processes: [String: Process] = [:]

    func register(_ process: Process, for id: String) {
        lock.lock()
        processes[id] = process
        lock.unlock()
    }

    func unregister(id: String) {
        lock.lock()
        processes[id] = nil
        lock.unlock()
    }

    func terminate(id: String) {
        lock.lock()
        let process = processes[id]
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

enum GitClientError: LocalizedError {
    case commandFailed(arguments: [String], exitCode: Int32, standardError: String)
    case outputDecodingFailed
    case localChangesPresent(repository: String)
    /// Git wanted a username/password (prompts are off, see `processEnvironment`).
    /// On GitHub that means the repo is private, or was renamed or deleted.
    case loginRequired
    /// A network command ran past its time limit and was stopped.
    case timedOut(arguments: [String], seconds: Int)
    /// git itself doesn't run (no Command Line Tools), see `GitAvailability`.
    case gitMissing

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, exitCode, standardError):
            let command = (["git"] + arguments).joined(separator: " ")
            let message = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) failed with exit code \(exitCode). \(message)"
        case .outputDecodingFailed:
            return "Could not decode Git command output."
        case let .localChangesPresent(repository):
            return "\(repository) has local changes — skipped to protect them."
        case .loginRequired:
            return "GitHub asked for a login: the repo is private, renamed or deleted. reshelf can only clone public repos."
        case let .timedOut(arguments, seconds):
            // The subcommand ("fetch", "ls-remote"), skipping `-c key=value` pairs.
            let subcommand = arguments.indices.first { index in
                arguments[index] != "-c" && (index == 0 || arguments[index - 1] != "-c")
            }.map { arguments[$0] } ?? ""
            return "git \(subcommand) got no answer within \(seconds) seconds and was stopped. Check the network and try again."
        case .gitMissing:
            return "reshelf needs Apple's Command Line Tools for git. Install them with xcode-select --install in Terminal, then try again."
        }
    }

    /// Git's messages when it needed credentials it could not ask for.
    static func isLoginFailure(_ standardError: String) -> Bool {
        ["terminal prompts disabled", "could not read Username", "could not read Password",
         "Authentication failed"].contains { standardError.contains($0) }
    }
}

/// Stops a git process that runs past its time limit: SIGTERM first (git
/// cleans up a half-written clone/fetch on it), SIGKILL 5 seconds later if it
/// is still there.
private final class GitTimeoutWatchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var workItem: DispatchWorkItem?

    var didFire: Bool {
        lock.lock(); defer { lock.unlock() }
        return fired
    }

    func arm(_ process: Process, seconds: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, process.isRunning else { return }
            self.lock.lock(); self.fired = true; self.lock.unlock()
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        lock.lock(); workItem = item; lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func disarm() {
        lock.lock(); workItem?.cancel(); lock.unlock()
    }
}

/// Whether git runs at all. On a Mac without Command Line Tools, /usr/bin/git
/// is a stub that offers to install them and exits non-zero, and its error
/// means nothing to the user. Asked only after a command failed, once per
/// launch; a "no" is asked again after a minute, so installing the tools
/// works without quitting reshelf.
final class GitAvailability: @unchecked Sendable {
    static let shared = GitAvailability()
    static let retryMissingAfter: TimeInterval = 60

    private let lock = NSLock()
    private var known: [String: (works: Bool, checkedAt: Date)] = [:]

    func works(_ executableURL: URL) async -> Bool {
        if let answer = cachedAnswer(for: executableURL.path) { return answer }
        let works = await Self.probe(executableURL)
        remember(works, for: executableURL.path)
        return works
    }

    private func cachedAnswer(for path: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = known[path] else { return nil }
        if entry.works || Date().timeIntervalSince(entry.checkedAt) < Self.retryMissingAfter { return entry.works }
        return nil
    }

    private func remember(_ works: Bool, for path: String) {
        lock.lock(); known[path] = (works, Date()); lock.unlock()
    }

    /// `git --version` exits 0. A probe that hangs is not proof git is missing.
    private static func probe(_ executableURL: URL) async -> Bool {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.environment = GitClient.processEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let watchdog = GitTimeoutWatchdog()
        let status: Int32? = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
                watchdog.arm(process, seconds: 15)
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil) // could not even launch
            }
        }
        watchdog.disarm()
        guard let status else { return false }
        return status == 0 || watchdog.didFire
    }
}

struct GitClient {
    var executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")

    /// Disable Git LFS smudge/process filters. Repos that use LFS (e.g. zotero)
    /// otherwise fail checkout with "git-lfs: command not found" when git-lfs isn't
    /// installed. reshelf clones are a source reference library and don't need the
    /// LFS binary assets, so LFS files are left as small pointer files —
    /// which is fine and removes any dependency on git-lfs being installed.
    private static let lfsBypass = [
        "-c", "filter.lfs.smudge=",
        "-c", "filter.lfs.clean=",
        "-c", "filter.lfs.process=",
        "-c", "filter.lfs.required=false"
    ]

    /// Time limits for network commands. Check and Pull walk the clones one by
    /// one, so one stuck server (or a prompt nobody answers) would stall the
    /// rest. `ls-remote` is one small round trip: 60 seconds is plenty. A fetch
    /// downloads what changed since the last pull: 10 minutes covers a big repo
    /// that is far behind. Clone has no limit (a large repo can take a long
    /// while); it gets the stall guard below instead.
    static let lsRemoteTimeout: TimeInterval = 60
    static let fetchTimeout: TimeInterval = 600

    /// Clone only: abort when the download stays under 1 KB/s for 5 minutes, so
    /// a dead connection doesn't hang a clone forever. GitHub sends keep-alive
    /// data while it packs, so a slow-to-start clone of a big repo is not hit.
    private static let stallGuard = [
        "-c", "http.lowSpeedLimit=1000",
        "-c", "http.lowSpeedTime=300"
    ]

    /// The environment git runs with: the app's own, plus no credential prompts.
    /// Launched from a terminal, git would otherwise wait on a username prompt
    /// for a private repo forever (from Finder there is no terminal, but a
    /// configured askpass helper could still pop a dialog). An empty
    /// GIT_ASKPASS switches off every askpass program (core.askPass and
    /// SSH_ASKPASS too); saved credential helpers (Keychain) still work.
    static func processEnvironment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = ""
        return environment
    }

    /// A normal full clone — what a user expects when they "clone to work on it."
    func clone(repositoryURL: String, destinationURL: URL, cancellationID: String? = nil) async throws {
        let arguments = Self.lfsBypass + Self.stallGuard + ["clone", repositoryURL, destinationURL.path]
        _ = try await run(arguments: arguments, cancellationID: cancellationID)
    }

    /// True when HEAD resolves to a commit. A clone killed after git wrote its
    /// config but before it finished has an origin and no HEAD commit.
    func headResolves(repositoryURL: URL) async -> Bool {
        (try? await run(arguments: ["rev-parse", "--verify", "--quiet", "HEAD^{commit}"],
                        workingDirectory: repositoryURL)) != nil
    }

    /// Sync a read-only reference clone to its upstream default branch. Fetches,
    /// then resets the clone to the remote default tip — a no-op fast-forward when
    /// already current, and the fix when upstream rewrote history (force-push /
    /// rebase) so a plain `pull --ff-only` would abort with "Not possible to
    /// fast-forward". Refuses (throws `.localChangesPresent`) if the working tree
    /// has *tracked* edits, so a hand-modified clone is never clobbered. Untracked
    /// files are left in place. LFS-bypassed like clone.
    func syncToUpstream(repositoryURL: URL, cancellationID: String? = nil) async throws {
        // Remember every commit the clone already knew from upstream *before* the
        // fetch: after a force-push, `--prune` drops the old upstream tip from
        // origin/*, and without this list a plain reference clone would look like
        // it holds "local" commits and never get past the check below.
        let knownUpstream = try await trimmedOutput(
            // Branches only: tags rarely move, and a repo with thousands of
            // them would overflow the argument list passed to rev-list.
            arguments: ["for-each-ref", "--format=%(objectname)", "refs/remotes"],
            workingDirectory: repositoryURL)
            .split(whereSeparator: \.isNewline).map(String.init)

        // `--force`: upstream sometimes re-points a release tag (re-tagged v2.0.1).
        // Without it git refuses to "clobber" the local tag and the whole sync
        // fails; a reference clone should simply mirror upstream's tags.
        _ = try await run(arguments: Self.lfsBypass + ["fetch", "origin", "--prune", "--tags", "--force"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID,
                          timeout: Self.fetchTimeout)

        guard try await workingTreeIsClean(repositoryURL: repositoryURL) else {
            throw GitClientError.localChangesPresent(repository: repositoryURL.lastPathComponent)
        }

        guard let branch = try await remoteDefaultBranch(repositoryURL: repositoryURL) else {
            throw GitClientError.outputDecodingFailed
        }

        // Commits made in the clone itself (on HEAD or on the local default
        // branch) that upstream never had. `checkout -B` below would drop them,
        // so a clone like that is skipped, the same way as one with edits.
        guard try await !hasLocalOnlyCommits(repositoryURL: repositoryURL, branch: branch,
                                             knownUpstream: knownUpstream,
                                             cancellationID: cancellationID) else {
            throw GitClientError.localChangesPresent(repository: repositoryURL.lastPathComponent)
        }

        // `checkout -B` lands HEAD on the default branch and points it at the
        // upstream tip in one step — covers an already-on-branch fast-forward, a
        // diverged reset, and a detached/other-branch checkout. Safe because the
        // tracked tree is clean.
        _ = try await run(arguments: Self.lfsBypass + ["checkout", "-B", branch, "origin/\(branch)"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)
    }

    /// True when HEAD (or the local `branch`, if it exists) reaches a commit that
    /// is on no remote-tracking branch or upstream tag, now or before the last
    /// fetch (`knownUpstream`). Fails closed: any doubt counts as local commits.
    func hasLocalOnlyCommits(repositoryURL: URL, branch: String, knownUpstream: [String],
                             cancellationID: String? = nil) async throws -> Bool {
        var tips = ["HEAD"]
        let localBranch = try? await trimmedOutput(
            arguments: ["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"],
            workingDirectory: repositoryURL)
        if let localBranch, !localBranch.isEmpty { tips.append(localBranch) }

        // `--tags` covers a clone detached on an upstream release tag whose commit
        // is on no upstream branch. Tags made in the clone itself must not count
        // as upstream, or a tagged local commit would be dropped by the reset.
        let upstreamTags = try await run(arguments: ["ls-remote", "--tags", "--refs", "origin"],
                                         workingDirectory: repositoryURL,
                                         cancellationID: cancellationID,
                                         timeout: Self.lsRemoteTimeout)
            .standardOutput.split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let ref = line.split(separator: "\t").last else { return nil }
                return ref.hasPrefix("refs/tags/") ? String(ref.dropFirst("refs/tags/".count)) : nil
            }
        let localTags = try await trimmedOutput(
            arguments: ["for-each-ref", "--format=%(refname:strip=2)", "refs/tags"],
            workingDirectory: repositoryURL)
            .split(whereSeparator: \.isNewline).map(String.init)
        let localOnlyTags = Set(localTags).subtracting(upstreamTags)
        // `--exclude` takes a glob; git forbids these characters in ref names,
        // so seeing one means something odd is going on.
        if localOnlyTags.contains(where: { tag in tag.contains(where: { "*?[\\".contains($0) }) }) {
            return true
        }

        let output = try await trimmedOutput(
            arguments: ["rev-list", "--count"] + tips + ["--not", "--remotes"]
                + localOnlyTags.sorted().map { "--exclude=\($0)" } + ["--tags"] + knownUpstream,
            workingDirectory: repositoryURL)
        guard let count = Int(output) else { return true }
        return count > 0
    }

    /// True when `ancestor` is a commit this clone has and HEAD contains it —
    /// i.e. the clone is level with or ahead of it. Read-only, no network.
    func headContains(_ ancestor: String, repositoryURL: URL) async -> Bool {
        (try? await run(arguments: ["merge-base", "--is-ancestor", ancestor, "HEAD"],
                        workingDirectory: repositoryURL)) != nil
    }

    /// True when the clone has no *tracked* modifications. Untracked files are
    /// ignored — they neither block a sync nor get removed by it. LFS-bypassed:
    /// without it, `git status` on an LFS repo spawns `git-lfs filter-process`,
    /// which fails ("git-lfs: command not found") when git-lfs isn't installed.
    func workingTreeIsClean(repositoryURL: URL) async throws -> Bool {
        let output = try await trimmedOutput(
            arguments: Self.lfsBypass + ["status", "--porcelain", "--untracked-files=no"],
            workingDirectory: repositoryURL)
        return output.isEmpty
    }

    /// The upstream default branch name (e.g. `master` / `main`), read fresh from
    /// the remote so it survives a default-branch rename. Parses the symref line of
    /// `git ls-remote --symref origin HEAD` ("ref: refs/heads/<name>\tHEAD").
    func remoteDefaultBranch(repositoryURL: URL, cancellationID: String? = nil) async throws -> String? {
        let result = try await run(arguments: ["ls-remote", "--symref", "origin", "HEAD"],
                                   workingDirectory: repositoryURL,
                                   cancellationID: cancellationID,
                                   timeout: Self.lsRemoteTimeout)
        let headsPrefix = "refs/heads/"
        for rawLine in result.standardOutput.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.hasPrefix("ref:") else { continue }
            let afterRef = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            guard let refToken = afterRef.split(whereSeparator: { $0 == "\t" || $0 == " " }).first else { continue }
            let ref = String(refToken)
            if ref.hasPrefix(headsPrefix) { return String(ref.dropFirst(headsPrefix.count)) }
        }
        return nil
    }

    func currentHead(repositoryURL: URL) async throws -> String? {
        try await trimmedOutput(arguments: ["rev-parse", "HEAD"], workingDirectory: repositoryURL)
    }

    /// The remote default branch's tip SHA — a cheap, read-only `ls-remote`
    /// (one network round-trip, no objects fetched, doesn't touch the clone).
    func remoteDefaultHead(repositoryURL: URL, cancellationID: String? = nil) async throws -> String? {
        let output = try await run(arguments: ["ls-remote", "origin", "HEAD"],
                                   workingDirectory: repositoryURL,
                                   cancellationID: cancellationID,
                                   timeout: Self.lsRemoteTimeout)
            .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Output line: "<sha>\tHEAD"
        return output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init)
    }

    /// - Parameter timeout: seconds before git is stopped and `.timedOut` thrown;
    ///   nil = no limit. Set for network commands only.
    func run(arguments: [String], workingDirectory: URL? = nil, cancellationID: String? = nil,
             timeout: TimeInterval? = nil) async throws -> GitCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.processEnvironment()
        // Git never needs our stdin; a prompt must not be able to read it.
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let cancellationID {
            GitProcessRegistry.shared.register(process, for: cancellationID)
        }
        defer {
            if let cancellationID {
                GitProcessRegistry.shared.unregister(id: cancellationID)
            }
        }

        // Drain both pipes WHILE git runs, off the cooperative pool, and wait for
        // exit via the termination handler. Two freezes this prevents: reading
        // only after waitUntilExit deadlocks as soon as git writes a pipe
        // buffer's worth (~64KB — e.g. a fetch that updates many refs), and
        // waitUntilExit inside a detached task parks a Swift-concurrency
        // cooperative thread for the whole clone, so a few clones in a row
        // starved the pool and hung every async task in the app.
        //
        // Unstructured tasks, not `async let`: after a timeout we throw without
        // waiting for EOF, because a child git started (git-remote-https) can
        // hold the pipes open after git itself is gone, and an `async let`
        // would be awaited on the way out anyway.
        let outputData = Task.detached { await Self.drain(outputPipe) }
        let errorData = Task.detached { await Self.drain(errorPipe) }

        let watchdog = GitTimeoutWatchdog()
        let terminationStatus: Int32
        do {
            terminationStatus = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                    if let timeout { watchdog.arm(process, seconds: timeout) }
                } catch {
                    process.terminationHandler = nil
                    // Never launched: close our write ends so the drains hit EOF
                    // instead of waiting forever on a child that doesn't exist.
                    try? outputPipe.fileHandleForWriting.close()
                    try? errorPipe.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            if await !GitAvailability.shared.works(executableURL) { throw GitClientError.gitMissing }
            throw error
        }
        watchdog.disarm()

        if terminationStatus != 0, watchdog.didFire, let timeout {
            throw GitClientError.timedOut(arguments: arguments, seconds: Int(timeout))
        }

        guard let standardOutput = String(data: await outputData.value, encoding: .utf8),
              let standardError = String(data: await errorData.value, encoding: .utf8) else {
            throw GitClientError.outputDecodingFailed
        }

        if terminationStatus != 0, GitClientError.isLoginFailure(standardError) {
            throw GitClientError.loginRequired
        }

        guard terminationStatus == 0 else {
            if await !GitAvailability.shared.works(executableURL) { throw GitClientError.gitMissing }
            throw GitClientError.commandFailed(
                arguments: arguments,
                exitCode: terminationStatus,
                standardError: standardError
            )
        }

        return GitCommandResult(standardOutput: standardOutput, standardError: standardError)
    }

    /// Read a pipe to EOF on GCD so large or slow git output never occupies a
    /// Swift-concurrency cooperative thread.
    private static func drain(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }

    private func trimmedOutput(arguments: [String], workingDirectory: URL) async throws -> String {
        let result = try await run(arguments: arguments, workingDirectory: workingDirectory)
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
