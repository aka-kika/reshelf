import Foundation
import GRDB

struct RepositoryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "repositories"

    var id: String
    var host: String
    var owner: String
    var name: String
    var fullName: String
    var githubURL: String
    var websiteURL: String?
    var defaultBranch: String?
    var localPath: String?
    var latestCommitSHA: String?
    var userStatus: String
    var addedAt: String
    var updatedAt: String
    var lastAnalyzedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case host
        case owner
        case name
        case fullName = "full_name"
        case githubURL = "github_url"
        case websiteURL = "website_url"
        case defaultBranch = "default_branch"
        case localPath = "local_path"
        case latestCommitSHA = "latest_commit_sha"
        case userStatus = "user_status"
        case addedAt = "added_at"
        case updatedAt = "updated_at"
        case lastAnalyzedAt = "last_analyzed_at"
    }
}
