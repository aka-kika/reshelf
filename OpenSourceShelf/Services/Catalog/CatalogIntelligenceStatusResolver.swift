import Foundation

enum CatalogIntelligencePipelineJob {
    static let types: Set<String> = [
        "fetch_github_metadata",
        "clone_repo",
        "static_analysis",
        "ai_analysis",
        "relationship_generation",
        "recommendation_generation"
    ]
}

enum CatalogIntelligenceStatusResolver {
    static func snapshot(for toolProject: ToolProject,
                         database: IntelligenceDatabase = .shared) -> CatalogIntelligenceStatusSnapshot {
        snapshot(githubURL: toolProject.githubURL,
                 projectName: toolProject.name,
                 database: database)
    }

    static func snapshot(githubURL: String,
                         projectName: String,
                         database: IntelligenceDatabase = .shared) -> CatalogIntelligenceStatusSnapshot {
        do {
            try database.initialize()
        } catch {
            return CatalogIntelligenceStatusSnapshot(status: .failed,
                                                       errorMessage: error.localizedDescription,
                                                       repositoryID: nil)
        }

        guard resolvedGitHubURL(githubURL: githubURL, projectName: projectName) != nil else {
            return .notFetched
        }

        guard let repository = findIntelligenceRepository(githubURL: githubURL,
                                                          projectName: projectName,
                                                          database: database) else {
            return .notFetched
        }

        if isReady(repositoryID: repository.id, database: database) {
            return CatalogIntelligenceStatusSnapshot(status: .ready,
                                                       errorMessage: nil,
                                                       repositoryID: repository.id)
        }

        if let activeStatus = activePipelineStatus(repositoryID: repository.id, database: database) {
            return CatalogIntelligenceStatusSnapshot(status: activeStatus,
                                                       errorMessage: nil,
                                                       repositoryID: repository.id)
        }

        if let failureMessage = latestPipelineFailureMessage(repositoryID: repository.id, database: database) {
            return CatalogIntelligenceStatusSnapshot(status: .failed,
                                                       errorMessage: failureMessage,
                                                       repositoryID: repository.id)
        }

        if (try? database.fetchMetadata(repositoryID: repository.id)) == nil {
            return CatalogIntelligenceStatusSnapshot(status: .notFetched,
                                                       errorMessage: nil,
                                                       repositoryID: repository.id)
        }

        return CatalogIntelligenceStatusSnapshot(status: .ready,
                                                   errorMessage: nil,
                                                   repositoryID: repository.id)
    }

    private static func resolvedGitHubURL(githubURL: String, projectName: String) -> String? {
        let trimmedURL = githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty, let parsed = GitHubRepositoryURL.parse(trimmedURL) {
            return parsed.canonicalURL
        }
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.contains("/"), let parsed = GitHubRepositoryURL.parseFullName(trimmedName) {
            return parsed.canonicalURL
        }
        return nil
    }

    private static func findIntelligenceRepository(githubURL: String,
                                                   projectName: String,
                                                   database: IntelligenceDatabase) -> RepositoryRecord? {
        let trimmedURL = githubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            if let parsed = GitHubRepositoryURL.parse(trimmedURL) {
                if let match = try? database.fetchRepository(githubURL: parsed.canonicalURL) {
                    return match
                }
                if let match = try? database.fetchRepository(fullName: parsed.fullName) {
                    return match
                }
            }
        }

        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.contains("/"),
           let parsed = GitHubRepositoryURL.parseFullName(trimmedName),
           let match = try? database.fetchRepository(fullName: parsed.fullName) {
            return match
        }

        if !trimmedName.isEmpty, !trimmedName.contains("/"),
           let match = try? database.fetchRepository(uniquelyByName: trimmedName) {
            return match
        }

        return nil
    }

    static func findRepository(githubURL: String,
                               projectName: String,
                               database: IntelligenceDatabase = .shared) -> RepositoryRecord? {
        do {
            try database.initialize()
        } catch {
            return nil
        }
        return findIntelligenceRepository(githubURL: githubURL,
                                          projectName: projectName,
                                          database: database)
    }

    static func isReady(repositoryID: String, database: IntelligenceDatabase = .shared) -> Bool {
        guard (try? database.fetchMetadata(repositoryID: repositoryID)) != nil else { return false }
        guard let active = try? database.fetchActivePipelineJobs(repositoryID: repositoryID), active.isEmpty else {
            return false
        }
        return true
    }

    private static func activePipelineStatus(repositoryID: String,
                                             database: IntelligenceDatabase) -> CatalogIntelligenceStatus? {
        guard let jobs = try? database.fetchActivePipelineJobs(repositoryID: repositoryID), !jobs.isEmpty else {
            if let cloneState = try? database.fetchCloneState(repositoryID: repositoryID),
               cloneState.status == "cloning" || cloneState.status == "fetching" {
                return .cloning
            }
            return nil
        }

        let runningJobs = jobs.filter { $0.status == "running" }
        if runningJobs.isEmpty {
            return .queued
        }

        if runningJobs.contains(where: { $0.type == "fetch_github_metadata" }) {
            return .fetching
        }
        if runningJobs.contains(where: { $0.type == "clone_repo" }) {
            return .cloning
        }
        if runningJobs.contains(where: { CatalogIntelligencePipelineJob.types.contains($0.type) && $0.type != "fetch_github_metadata" && $0.type != "clone_repo" }) {
            return .analyzing
        }

        if let cloneState = try? database.fetchCloneState(repositoryID: repositoryID),
           cloneState.status == "cloning" || cloneState.status == "fetching" {
            return .cloning
        }

        return .analyzing
    }

    private static func latestPipelineFailureMessage(repositoryID: String,
                                                     database: IntelligenceDatabase) -> String? {
        guard let job = try? database.fetchLatestFailedPipelineJob(repositoryID: repositoryID) else {
            return nil
        }
        return job.error ?? job.displayTypeFallback
    }
}

private extension IngestionJobRecord {
    var displayTypeFallback: String {
        type.replacingOccurrences(of: "_", with: " ").capitalized + " failed."
    }
}
