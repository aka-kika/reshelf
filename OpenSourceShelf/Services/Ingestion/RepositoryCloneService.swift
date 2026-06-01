import Foundation

/// Resolves the root folder where repositories are cloned. The user can override
/// it in Settings; otherwise it defaults to `~/reshelf/repos`. Stored as a
/// plain path in UserDefaults (the app is not sandboxed, so no security-scoped
/// bookmark is needed). Existing clones are unaffected — only new clones use the
/// current value.
enum CloneLocation {
    static let storageKey = "reshelf.cloneRootPath"

    static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("reshelf", isDirectory: true)
            .appendingPathComponent("repos", isDirectory: true)
    }

    /// `true` when the user has chosen a custom folder (a non-empty stored path).
    static var isCustom: Bool {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return false }
        return !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var rootURL: URL {
        if let stored = UserDefaults.standard.string(forKey: storageKey) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed, isDirectory: true)
            }
        }
        return defaultRootURL
    }
}

struct RepositoryCloneResult: Equatable {
    let repository: RepositoryRecord
    let cloneState: CloneStateRecord
    let ingestionJob: IngestionJobRecord
}

enum RepositoryCloneError: LocalizedError {
    case unsafeRepositoryIdentity
    case destinationExistsWithoutGitRepository(String)

    var errorDescription: String? {
        switch self {
        case .unsafeRepositoryIdentity:
            return "Repository identity is not safe to use as a local clone path."
        case let .destinationExistsWithoutGitRepository(path):
            return "Clone destination exists but is not a Git repository: \(path)"
        }
    }
}

enum RepositoryCloneService {
    static func cloneOrFetch(repository: RepositoryRecord,
                             database: IntelligenceDatabase = .shared,
                             gitClient: GitClient = GitClient(),
                             fileManager: FileManager = .default,
                             cloneRootURL: URL? = nil,
                             jobID: String? = nil) async throws -> RepositoryCloneResult {
        guard let repositoryIdentity = GitHubRepositoryURL.parseFullName(repository.fullName),
              repository.host == repositoryIdentity.host,
              repository.owner == repositoryIdentity.owner,
              repository.name == repositoryIdentity.name else {
            throw RepositoryCloneError.unsafeRepositoryIdentity
        }

        try database.initialize()

        let rootURL = cloneRootURL ?? CloneLocation.rootURL
        let destinationURL = rootURL
            .appendingPathComponent(repositoryIdentity.host, isDirectory: true)
            .appendingPathComponent(repositoryIdentity.owner, isDirectory: true)
            .appendingPathComponent(repositoryIdentity.name, isDirectory: true)
            .appendingPathComponent("worktree", isDirectory: true)

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(
            id: jobID ?? UUID().uuidString,
            repositoryID: repository.id,
            type: "clone_repo",
            status: "running",
            priority: 0,
            progress: 0.1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: nil
        )

        var updatedRepository = repository
        updatedRepository.localPath = destinationURL.path
        updatedRepository.updatedAt = now

        var cloneState = CloneStateRecord(
            repositoryID: repository.id,
            status: "cloning",
            cloneMode: "blobless",
            path: destinationURL.path,
            currentHead: nil,
            branchCount: nil,
            tagCount: nil,
            sizeBytes: nil,
            lastFetchAt: nil,
            lastError: nil
        )

        try database.upsert(repository: updatedRepository,
                            cloneState: cloneState,
                            ingestionJob: job)
        if try database.isIngestionJobCancelled(id: job.id) {
            return try cancelledResult(repository: updatedRepository,
                                       cloneState: cloneState,
                                       job: job,
                                       database: database)
        }

        do {
            let parentURL = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationURL.path) {
                guard fileManager.fileExists(atPath: destinationURL.appendingPathComponent(".git", isDirectory: true).path) else {
                    throw RepositoryCloneError.destinationExistsWithoutGitRepository(destinationURL.path)
                }

                cloneState.status = "fetching"
                job.progress = 0.4
                try database.upsert(repository: updatedRepository,
                                    cloneState: cloneState,
                                    ingestionJob: job)
                try await gitClient.fetch(repositoryURL: destinationURL, cancellationID: job.id)
                if try database.isIngestionJobCancelled(id: job.id) {
                    return try cancelledResult(repository: updatedRepository,
                                               cloneState: cloneState,
                                               job: job,
                                               database: database)
                }
                try await gitClient.pullFastForward(repositoryURL: destinationURL, cancellationID: job.id)
            } else {
                try await gitClient.clone(repositoryURL: repositoryIdentity.canonicalURL,
                                          destinationURL: destinationURL,
                                          cancellationID: job.id)
            }

            if try database.isIngestionJobCancelled(id: job.id) {
                return try cancelledResult(repository: updatedRepository,
                                           cloneState: cloneState,
                                           job: job,
                                           database: database)
            }

            let completedAt = IntelligenceDatabase.iso8601String()
            let currentHead = try await gitClient.currentHead(repositoryURL: destinationURL)
            let branchCount = try await gitClient.branchCount(repositoryURL: destinationURL)
            let tagCount = try await gitClient.tagCount(repositoryURL: destinationURL)
            let sizeBytes = directorySize(at: destinationURL, fileManager: fileManager)

            updatedRepository.latestCommitSHA = currentHead
            updatedRepository.localPath = destinationURL.path
            updatedRepository.updatedAt = completedAt

            cloneState.status = "cloned"
            cloneState.path = destinationURL.path
            cloneState.currentHead = currentHead
            cloneState.branchCount = branchCount
            cloneState.tagCount = tagCount
            cloneState.sizeBytes = sizeBytes
            cloneState.lastFetchAt = completedAt
            cloneState.lastError = nil

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt

            try database.upsert(repository: updatedRepository,
                                cloneState: cloneState,
                                ingestionJob: job)

            do {
                _ = try await RepositoryStaticAnalyzer.analyze(repository: updatedRepository, database: database)
            } catch {
                #if DEBUG
                print("[reshelf] Static analysis failed for \(updatedRepository.fullName): \(error)")
                #endif
            }

            return RepositoryCloneResult(repository: updatedRepository,
                                         cloneState: cloneState,
                                         ingestionJob: job)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true {
                return try cancelledResult(repository: updatedRepository,
                                           cloneState: cloneState,
                                           job: job,
                                           database: database)
            }

            let failedAt = IntelligenceDatabase.iso8601String()
            cloneState.status = "failed"
            cloneState.path = destinationURL.path
            cloneState.lastError = error.localizedDescription

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = failedAt

            try? database.upsert(repository: updatedRepository,
                                 cloneState: cloneState,
                                 ingestionJob: job)
            throw error
        }
    }

    private static func cancelledResult(repository: RepositoryRecord,
                                        cloneState: CloneStateRecord,
                                        job: IngestionJobRecord,
                                        database: IntelligenceDatabase) throws -> RepositoryCloneResult {
        var cancelledCloneState = cloneState
        var cancelledJob = job
        let cancelledAt = IntelligenceDatabase.iso8601String()

        cancelledCloneState.status = "cancelled"
        cancelledCloneState.lastError = "Cancelled by user."

        cancelledJob.status = "cancelled"
        cancelledJob.progress = 1
        cancelledJob.error = "Cancelled by user."
        cancelledJob.completedAt = cancelledAt

        try database.upsert(repository: repository,
                            cloneState: cancelledCloneState,
                            ingestionJob: cancelledJob)

        return RepositoryCloneResult(repository: repository,
                                     cloneState: cancelledCloneState,
                                     ingestionJob: cancelledJob)
    }

    private static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            size += Int64(fileSize)
        }
        return size
    }
}
