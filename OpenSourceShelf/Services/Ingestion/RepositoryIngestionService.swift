import Foundation

struct RepositoryIngestionResult: Equatable {
    let repository: RepositoryRecord
    let metadata: RepositoryMetadataRecord
    let cloneState: CloneStateRecord
    let ingestionJob: IngestionJobRecord
}

enum RepositoryIngestionError: LocalizedError {
    case invalidGitHubURL
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidGitHubURL:
            "Not a valid GitHub repository URL."
        case .cancelled:
            "Ingestion was cancelled."
        }
    }
}

enum RepositoryIngestionService {
    static func ingestMetadata(githubURL rawURL: String,
                               database: IntelligenceDatabase = .shared,
                               jobID: String? = nil) async throws -> RepositoryIngestionResult {
        guard let parsedURL = GitHubRepositoryURL.parse(rawURL) else {
            throw RepositoryIngestionError.invalidGitHubURL
        }

        try database.initialize()

        let now = IntelligenceDatabase.iso8601String()
        let existingRepository = try database.fetchRepository(fullName: parsedURL.fullName)
        let repositoryID = existingRepository?.id ?? UUID().uuidString
        let existingCloneState = try database.fetchCloneState(repositoryID: repositoryID)

        var job = IngestionJobRecord(
            id: jobID ?? UUID().uuidString,
            repositoryID: repositoryID,
            type: "fetch_github_metadata",
            status: "running",
            priority: 0,
            progress: 0.1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: nil
        )

        let initialRepository = RepositoryRecord(
            id: repositoryID,
            host: parsedURL.host,
            owner: parsedURL.owner,
            name: parsedURL.name,
            fullName: parsedURL.fullName,
            githubURL: parsedURL.canonicalURL,
            websiteURL: existingRepository?.websiteURL,
            defaultBranch: existingRepository?.defaultBranch,
            localPath: existingRepository?.localPath,
            latestCommitSHA: existingRepository?.latestCommitSHA,
            userStatus: existingRepository?.userStatus ?? "new",
            addedAt: existingRepository?.addedAt ?? now,
            updatedAt: now,
            lastAnalyzedAt: existingRepository?.lastAnalyzedAt
        )

        let initialCloneState = existingCloneState ?? CloneStateRecord(
            repositoryID: repositoryID,
            status: "not_cloned",
            cloneMode: "metadata_only",
            path: nil,
            currentHead: nil,
            branchCount: nil,
            tagCount: nil,
            sizeBytes: nil,
            lastFetchAt: nil,
            lastError: nil
        )

        try database.upsert(repository: initialRepository,
                            cloneState: initialCloneState,
                            ingestionJob: job)
        if try database.isIngestionJobCancelled(id: job.id) {
            throw RepositoryIngestionError.cancelled
        }

        do {
            let info = try await QuickCaptureService.fetchRepoInfo(githubURL: parsedURL.canonicalURL)
            let completedAt = IntelligenceDatabase.iso8601String()
            if try database.isIngestionJobCancelled(id: job.id) {
                throw RepositoryIngestionError.cancelled
            }

            let canonicalURL = info.htmlUrl.flatMap(GitHubRepositoryURL.parse)
            let canonicalFullName = info.fullName.flatMap(GitHubRepositoryURL.parseFullName)
            var repositoryIdentity = canonicalURL ?? canonicalFullName ?? parsedURL

            // A renamed repo can sit on the shelf under both its old and new
            // slugs; GitHub redirects the old one and reports the new
            // canonical identity. If another repository row already owns that
            // identity, keep this row's own slug — adopting the canonical one
            // collides with the UNIQUE full_name/github_url columns and the
            // job would fail permanently on every retry.
            if repositoryIdentity.fullName != parsedURL.fullName {
                let fullNameOwner = (try? database.fetchRepository(fullName: repositoryIdentity.fullName)) ?? nil
                let urlOwner = (try? database.fetchRepository(githubURL: repositoryIdentity.canonicalURL)) ?? nil
                if fullNameOwner.map({ $0.id != repositoryID }) == true
                    || urlOwner.map({ $0.id != repositoryID }) == true {
                    repositoryIdentity = parsedURL
                }
            }

            let repository = RepositoryRecord(
                id: repositoryID,
                host: repositoryIdentity.host,
                owner: repositoryIdentity.owner,
                name: repositoryIdentity.name,
                fullName: repositoryIdentity.fullName,
                githubURL: repositoryIdentity.canonicalURL,
                websiteURL: emptyStringAsNil(info.homepage),
                defaultBranch: info.defaultBranch,
                localPath: existingRepository?.localPath,
                latestCommitSHA: existingRepository?.latestCommitSHA,
                userStatus: existingRepository?.userStatus ?? "new",
                addedAt: existingRepository?.addedAt ?? now,
                updatedAt: completedAt,
                lastAnalyzedAt: existingRepository?.lastAnalyzedAt
            )

            let metadata = RepositoryMetadataRecord(
                repositoryID: repositoryID,
                description: info.description,
                stars: info.stars,
                forks: info.forks,
                openIssues: info.openIssues,
                licenseSPDX: info.license?.spdxId ?? info.license?.name,
                topicsJSON: topicsJSON(info.topics ?? []),
                primaryLanguage: info.language,
                pushedAt: info.pushedAt,
                archived: info.archived ?? false,
                fork: info.fork ?? false
            )

            let cloneState = existingCloneState ?? CloneStateRecord(
                repositoryID: repositoryID,
                status: "not_cloned",
                cloneMode: "metadata_only",
                path: existingRepository?.localPath,
                currentHead: nil,
                branchCount: nil,
                tagCount: nil,
                sizeBytes: nil,
                lastFetchAt: nil,
                lastError: nil
            )

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt

            try database.upsert(repository: repository,
                                metadata: metadata,
                                cloneState: cloneState,
                                ingestionJob: job)

            return RepositoryIngestionResult(repository: repository,
                                             metadata: metadata,
                                             cloneState: cloneState,
                                             ingestionJob: job)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true {
                throw error
            }

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = IntelligenceDatabase.iso8601String()
            try? database.upsert(ingestionJob: job)
            throw error
        }
    }

    private static func emptyStringAsNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func topicsJSON(_ topics: [String]) -> String {
        let data = (try? JSONEncoder().encode(topics)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
