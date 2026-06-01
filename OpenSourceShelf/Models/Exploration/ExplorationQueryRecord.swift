import Foundation
import GRDB

struct ExplorationQueryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "exploration_queries"

    var id: String
    var queryText: String
    var normalizedIntent: String
    var filtersJSON: String
    var resultIDsJSON: String
    var isFavorite: Bool
    var createdAt: String
    var lastUsedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case queryText = "query_text"
        case normalizedIntent = "normalized_intent"
        case filtersJSON = "filters_json"
        case resultIDsJSON = "result_ids_json"
        case isFavorite = "is_favorite"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}
