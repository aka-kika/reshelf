import Foundation
import SwiftData

// Stand-ins for the GitHub client and the after-save helpers the import calls.
// The tests pass their own fetch, so nothing here talks to the network.
struct GitHubRepoInfo {
    var fullName: String?
    var description: String?
    var homepage: String?
    var stars: Int?
    var topics: [String]?
    var language: String?
    var pushedAt: String?
    var licenseText: String { "MIT" }
    static func formattedStars(_ count: Int) -> String { "\(count)" }
}

enum CaptureError: Error {
    case notFound(String)
    case rateLimited(resetText: String?)
}

enum QuickCaptureService {
    static func fetchRepoInfo(githubURL: String) async throws -> GitHubRepoInfo {
        throw CaptureError.notFound(githubURL)
    }
}

enum CatalogCaptureIntelligenceService {
    static func upsertFromCatalogSave(_ project: ToolProject, prefetched: GitHubRepoInfo? = nil) {}
}

enum IconFetcher {
    static func fetch(for project: ToolProject, in context: ModelContext) {}
}
