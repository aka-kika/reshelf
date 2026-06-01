import Foundation
import GRDB

struct RepositoryScoreRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "repository_scores"

    var id: String
    var repositoryID: String
    var cacheKey: String
    var setupComplexity: Int
    var localFirstScore: Int
    var experimentationPriority: Int
    var ecosystemInfluence: Int
    var personalRelevance: Int
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case cacheKey = "cache_key"
        case setupComplexity = "setup_complexity"
        case localFirstScore = "local_first_score"
        case experimentationPriority = "experimentation_priority"
        case ecosystemInfluence = "ecosystem_influence"
        case personalRelevance = "personal_relevance"
        case generatedAt = "generated_at"
    }
}
