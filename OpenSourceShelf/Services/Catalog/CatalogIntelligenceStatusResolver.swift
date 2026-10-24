import Foundation

enum CatalogIntelligenceStatusResolver {
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

        // A bare name ("tool") can be another owner's repo. Only owner/name matches.
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
}
