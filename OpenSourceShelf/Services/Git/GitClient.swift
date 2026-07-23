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
        }
    }
}

struct GitClient {
    var executableURL: URL = URL(fileURLWithPath: "/usr/bin/git")

    /// Disable Git LFS smudge/process filters. Repos that use LFS (e.g. zotero)
    /// otherwise fail checkout with "git-lfs: command not found" when git-lfs isn't
    /// installed. reshelf only needs the source tree for stack analysis / runbooks,
    /// not the LFS binary assets, so LFS files are left as small pointer files —
    /// which is fine and removes any dependency on git-lfs being installed.
    private static let lfsBypass = [
        "-c", "filter.lfs.smudge=",
        "-c", "filter.lfs.clean=",
        "-c", "filter.lfs.process=",
        "-c", "filter.lfs.required=false"
    ]

    /// - Parameter blobless: when true, a partial (`--filter=blob:none`) clone —
    ///   lighter, used by the intelligence pipeline. When false, a normal full
    ///   clone — what a user expects when they "clone to work on it."
    func clone(repositoryURL: String, destinationURL: URL, blobless: Bool = true, cancellationID: String? = nil) async throws {
        var arguments = Self.lfsBypass + ["clone"]
        if blobless { arguments.append("--filter=blob:none") }
        arguments += [repositoryURL, destinationURL.path]
        _ = try await run(arguments: arguments, cancellationID: cancellationID)
    }

    func fetch(repositoryURL: URL, cancellationID: String? = nil) async throws {
        _ = try await run(arguments: ["fetch", "--prune", "--tags"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)
    }

    /// Fast-forward-only pull (LFS-bypassed). Used by the intelligence ingestion
    /// pipeline, which manages its own divergence handling. The catalog's
    /// user-facing update path uses `syncToUpstream` instead, which also recovers
    /// from diverged clones.
    func pullFastForward(repositoryURL: URL, cancellationID: String? = nil) async throws {
        _ = try await run(arguments: Self.lfsBypass + ["pull", "--ff-only"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)
    }

    /// Sync a read-only reference clone to its upstream default branch. Fetches,
    /// then resets the clone to the remote default tip — a no-op fast-forward when
    /// already current, and the fix when upstream rewrote history (force-push /
    /// rebase) so a plain `pull --ff-only` would abort with "Not possible to
    /// fast-forward". Refuses (throws `.localChangesPresent`) if the working tree
    /// has *tracked* edits, so a hand-modified clone is never clobbered. Untracked
    /// files are left in place. LFS-bypassed like clone.
    func syncToUpstream(repositoryURL: URL, cancellationID: String? = nil) async throws {
        _ = try await run(arguments: Self.lfsBypass + ["fetch", "origin", "--prune", "--tags"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)

        guard try await workingTreeIsClean(repositoryURL: repositoryURL) else {
            throw GitClientError.localChangesPresent(repository: repositoryURL.lastPathComponent)
        }

        guard let branch = try await remoteDefaultBranch(repositoryURL: repositoryURL) else {
            throw GitClientError.outputDecodingFailed
        }

        // `checkout -B` lands HEAD on the default branch and points it at the
        // upstream tip in one step — covers an already-on-branch fast-forward, a
        // diverged reset, and a detached/other-branch checkout. Safe because the
        // tracked tree is clean.
        _ = try await run(arguments: Self.lfsBypass + ["checkout", "-B", branch, "origin/\(branch)"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)
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
                                   cancellationID: cancellationID)
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
        let output = try await trimmedOutput(arguments: ["ls-remote", "origin", "HEAD"],
                                             workingDirectory: repositoryURL)
        // Output line: "<sha>\tHEAD"
        return output.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init)
    }

    func branchCount(repositoryURL: URL) async throws -> Int {
        let output = try await trimmedOutput(arguments: ["branch", "--list", "--all"], workingDirectory: repositoryURL)
        return lineCount(output)
    }

    func tagCount(repositoryURL: URL) async throws -> Int {
        let output = try await trimmedOutput(arguments: ["tag", "--list"], workingDirectory: repositoryURL)
        return lineCount(output)
    }

    func run(arguments: [String], workingDirectory: URL? = nil, cancellationID: String? = nil) async throws -> GitCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

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
        async let outputData = Self.drain(outputPipe)
        async let errorData = Self.drain(errorPipe)

        let terminationStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                // Never launched: close our write ends so the drains hit EOF
                // instead of waiting forever on a child that doesn't exist.
                try? outputPipe.fileHandleForWriting.close()
                try? errorPipe.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }

        guard let standardOutput = String(data: await outputData, encoding: .utf8),
              let standardError = String(data: await errorData, encoding: .utf8) else {
            throw GitClientError.outputDecodingFailed
        }

        guard terminationStatus == 0 else {
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

    private func lineCount(_ output: String) -> Int {
        output.split(whereSeparator: \.isNewline).count
    }
}
