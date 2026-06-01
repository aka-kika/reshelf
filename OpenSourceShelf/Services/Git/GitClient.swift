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

    var errorDescription: String? {
        switch self {
        case let .commandFailed(arguments, exitCode, standardError):
            let command = (["git"] + arguments).joined(separator: " ")
            let message = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) failed with exit code \(exitCode). \(message)"
        case .outputDecodingFailed:
            return "Could not decode Git command output."
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

    func clone(repositoryURL: String, destinationURL: URL, cancellationID: String? = nil) async throws {
        _ = try await run(arguments: Self.lfsBypass + [
            "clone",
            "--filter=blob:none",
            repositoryURL,
            destinationURL.path
        ], cancellationID: cancellationID)
    }

    func fetch(repositoryURL: URL, cancellationID: String? = nil) async throws {
        _ = try await run(arguments: ["fetch", "--prune", "--tags"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)
    }

    func pullFastForward(repositoryURL: URL, cancellationID: String? = nil) async throws {
        _ = try await run(arguments: Self.lfsBypass + ["pull", "--ff-only"],
                          workingDirectory: repositoryURL,
                          cancellationID: cancellationID)
    }

    func currentHead(repositoryURL: URL) async throws -> String? {
        try await trimmedOutput(arguments: ["rev-parse", "HEAD"], workingDirectory: repositoryURL)
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
        try await Task.detached(priority: .utility) {
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

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard let standardOutput = String(data: outputData, encoding: .utf8),
                  let standardError = String(data: errorData, encoding: .utf8) else {
                throw GitClientError.outputDecodingFailed
            }

            guard process.terminationStatus == 0 else {
                throw GitClientError.commandFailed(
                    arguments: arguments,
                    exitCode: process.terminationStatus,
                    standardError: standardError
                )
            }

            return GitCommandResult(standardOutput: standardOutput, standardError: standardError)
        }.value
    }

    private func trimmedOutput(arguments: [String], workingDirectory: URL) async throws -> String {
        let result = try await run(arguments: arguments, workingDirectory: workingDirectory)
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lineCount(_ output: String) -> Int {
        output.split(whereSeparator: \.isNewline).count
    }
}
