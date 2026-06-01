import Foundation
import GRDB

struct RepositoryRecommendationRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "repository_recommendations"

    var id: String
    var sourceRepositoryID: String
    var targetNodeID: String
    var targetRepositoryID: String?
    var recommendationType: String
    var score: Double
    var explanation: String
    var signalsJSON: String
    var cacheKey: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sourceRepositoryID = "source_repository_id"
        case targetNodeID = "target_node_id"
        case targetRepositoryID = "target_repository_id"
        case recommendationType = "recommendation_type"
        case score
        case explanation
        case signalsJSON = "signals_json"
        case cacheKey = "cache_key"
        case generatedAt = "generated_at"
    }
}

struct RepositoryRecommendationSummary: Identifiable, Equatable {
    var id: String
    var sourceRepositoryID: String
    var targetNodeID: String
    var targetRepositoryID: String?
    var targetType: String
    var targetKey: String
    var targetLabel: String
    var recommendationType: String
    var score: Double
    var explanation: String
    var signalsJSON: String
    var generatedAt: String

    init(row: Row) {
        id = row["id"]
        sourceRepositoryID = row["source_repository_id"]
        targetNodeID = row["target_node_id"]
        targetRepositoryID = row["target_repository_id"]
        targetType = row["target_type"]
        targetKey = row["target_key"]
        targetLabel = row["target_label"]
        recommendationType = row["recommendation_type"]
        score = row["score"]
        explanation = row["explanation"]
        signalsJSON = row["signals_json"]
        generatedAt = row["generated_at"]
    }
}
