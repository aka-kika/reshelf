import Foundation
import GRDB

struct RepositoryMetadataRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "repository_metadata"

    var repositoryID: String
    var description: String?
    var stars: Int?
    var forks: Int?
    var openIssues: Int?
    var licenseSPDX: String?
    var topicsJSON: String
    var primaryLanguage: String?
    var pushedAt: String?
    var archived: Bool
    var fork: Bool

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case description
        case stars
        case forks
        case openIssues = "open_issues"
        case licenseSPDX = "license_spdx"
        case topicsJSON = "topics_json"
        case primaryLanguage = "primary_language"
        case pushedAt = "pushed_at"
        case archived
        case fork
    }
}
