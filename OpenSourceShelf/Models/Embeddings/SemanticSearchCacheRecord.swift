import Foundation
import GRDB

struct SemanticSearchCacheRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "semantic_search_cache"

    var id: String { queryHash }

    var queryHash: String
    var queryText: String
    var resultsJSON: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case queryHash = "query_hash"
        case queryText = "query_text"
        case resultsJSON = "results_json"
        case createdAt = "created_at"
    }
}

struct SemanticIndexState: Codable, Equatable {
    var cacheKey: String
    var chunkCount: Int
    var embeddingModel: String
}

struct SemanticMatch: Identifiable, Equatable, Codable {
    var id: String
    var repositoryID: String
    var sourceType: String
    var chunkText: String
    var similarity: Double
}
