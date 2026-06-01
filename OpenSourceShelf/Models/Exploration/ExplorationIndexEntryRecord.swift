import Foundation
import GRDB

struct ExplorationIndexEntryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "exploration_index_entries"

    var id: String
    var entryType: String
    var targetID: String
    var repositoryID: String?
    var title: String
    var subtitle: String
    var body: String
    var ecosystemName: String?
    var keywordsJSON: String
    var signalsJSON: String
    var score: Double
    var confidence: Double
    var cacheKey: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case entryType = "entry_type"
        case targetID = "target_id"
        case repositoryID = "repository_id"
        case title
        case subtitle
        case body
        case ecosystemName = "ecosystem_name"
        case keywordsJSON = "keywords_json"
        case signalsJSON = "signals_json"
        case score
        case confidence
        case cacheKey = "cache_key"
        case generatedAt = "generated_at"
    }
}

struct ExplorationIndexEntrySummary: Identifiable, Equatable {
    var id: String
    var entryType: String
    var targetID: String
    var repositoryID: String?
    var title: String
    var subtitle: String
    var body: String
    var ecosystemName: String?
    var keywordsJSON: String
    var signalsJSON: String
    var score: Double
    var confidence: Double

    init(row: Row) {
        id = row["id"]
        entryType = row["entry_type"]
        targetID = row["target_id"]
        repositoryID = row["repository_id"]
        title = row["title"]
        subtitle = row["subtitle"]
        body = row["body"]
        ecosystemName = row["ecosystem_name"]
        keywordsJSON = row["keywords_json"]
        signalsJSON = row["signals_json"]
        score = row["score"]
        confidence = row["confidence"]
    }
}
