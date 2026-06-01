import Foundation
import GRDB

struct AIInsightRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "ai_insights"

    var id: String
    var repositoryID: String
    var cacheKey: String
    var modelName: String
    var promptVersion: String
    var commitSHA: String?
    var summary: String
    var usefulness: String
    var classificationsJSON: String
    var risksJSON: String
    var relationshipHintsJSON: String
    var rawJSON: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case cacheKey = "cache_key"
        case modelName = "model_name"
        case promptVersion = "prompt_version"
        case commitSHA = "commit_sha"
        case summary
        case usefulness
        case classificationsJSON = "classifications_json"
        case risksJSON = "risks_json"
        case relationshipHintsJSON = "relationship_hints_json"
        case rawJSON = "raw_json"
        case generatedAt = "generated_at"
    }
}
