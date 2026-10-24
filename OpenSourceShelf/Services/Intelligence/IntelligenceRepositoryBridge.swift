import Foundation

enum IntelligenceRepositoryBridge {
    /// Resolves a SwiftData catalog project to its GRDB intelligence repository row.
    static func findIntelligenceRepository(for toolProject: ToolProject,
                                           database: IntelligenceDatabase = .shared) -> RepositoryRecord? {
        do {
            try database.initialize()
        } catch {
            return nil
        }

        let githubURL = toolProject.githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !githubURL.isEmpty {
            if let parsed = GitHubRepositoryURL.parse(githubURL) {
                if let match = try? database.fetchRepository(githubURL: parsed.canonicalURL) {
                    return match
                }
                if let match = try? database.fetchRepository(fullName: parsed.fullName) {
                    return match
                }
            }
        }

        let name = toolProject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains("/"),
           let parsed = GitHubRepositoryURL.parseFullName(name),
           let match = try? database.fetchRepository(fullName: parsed.fullName) {
            return match
        }

        // A bare name ("tool") can belong to another owner. Do not use it.
        return nil
    }

    static func parseGitHubIdentity(for toolProject: ToolProject) -> GitHubRepositoryURL? {
        let githubURL = toolProject.githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !githubURL.isEmpty, let parsed = GitHubRepositoryURL.parse(githubURL) {
            return parsed
        }

        let name = toolProject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains("/"), let parsed = GitHubRepositoryURL.parseFullName(name) {
            return parsed
        }

        return nil
    }

    /// Creates a minimal GRDB repository row when a valid GitHub identity exists and no row is present yet.
    @discardableResult
    static func createIntelligenceRepositoryIfNeeded(for toolProject: ToolProject,
                                                       database: IntelligenceDatabase = .shared) throws -> RepositoryRecord? {
        if let existing = findIntelligenceRepository(for: toolProject, database: database) {
            return existing
        }

        guard let parsed = parseGitHubIdentity(for: toolProject) else {
            return nil
        }

        try database.initialize()

        let now = IntelligenceDatabase.iso8601String()
        let repository = RepositoryRecord(
            id: UUID().uuidString,
            host: parsed.host,
            owner: parsed.owner,
            name: parsed.name,
            fullName: parsed.fullName,
            githubURL: parsed.canonicalURL,
            websiteURL: emptyStringAsNil(toolProject.websiteURL),
            defaultBranch: nil,
            localPath: nil,
            latestCommitSHA: nil,
            userStatus: toolProject.status.rawValue,
            addedAt: now,
            updatedAt: now,
            lastAnalyzedAt: nil
        )

        let cloneState = CloneStateRecord(
            repositoryID: repository.id,
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

        try database.upsert(repository: repository, cloneState: cloneState)
        return repository
    }

    private static func emptyStringAsNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
