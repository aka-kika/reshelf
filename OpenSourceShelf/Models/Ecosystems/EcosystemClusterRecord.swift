import Foundation
import GRDB

struct EcosystemClusterRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "ecosystem_clusters"

    var id: String
    var clusterType: String
    var name: String
    var score: Double
    var confidence: Double
    var repositoryIDsJSON: String
    var repositoryNamesJSON: String
    var commonStackJSON: String
    var strongestToolsJSON: String
    var integrationsJSON: String
    var recommendationHighlightsJSON: String
    var missingPiecesJSON: String
    var signalsJSON: String
    var explanation: String
    var cacheKey: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case clusterType = "cluster_type"
        case name
        case score
        case confidence
        case repositoryIDsJSON = "repository_ids_json"
        case repositoryNamesJSON = "repository_names_json"
        case commonStackJSON = "common_stack_json"
        case strongestToolsJSON = "strongest_tools_json"
        case integrationsJSON = "integrations_json"
        case recommendationHighlightsJSON = "recommendation_highlights_json"
        case missingPiecesJSON = "missing_pieces_json"
        case signalsJSON = "signals_json"
        case explanation
        case cacheKey = "cache_key"
        case generatedAt = "generated_at"
    }
}

struct EcosystemClusterSummary: Identifiable, Equatable {
    var id: String
    var clusterType: String
    var name: String
    var score: Double
    var confidence: Double
    var repositoryIDsJSON: String
    var repositoryNamesJSON: String
    var commonStackJSON: String
    var strongestToolsJSON: String
    var integrationsJSON: String
    var recommendationHighlightsJSON: String
    var missingPiecesJSON: String
    var signalsJSON: String
    var explanation: String
    var generatedAt: String

    init(row: Row) {
        id = row["id"]
        clusterType = row["cluster_type"]
        name = row["name"]
        score = row["score"]
        confidence = row["confidence"]
        repositoryIDsJSON = row["repository_ids_json"]
        repositoryNamesJSON = row["repository_names_json"]
        commonStackJSON = row["common_stack_json"]
        strongestToolsJSON = row["strongest_tools_json"]
        integrationsJSON = row["integrations_json"]
        recommendationHighlightsJSON = row["recommendation_highlights_json"]
        missingPiecesJSON = row["missing_pieces_json"]
        signalsJSON = row["signals_json"]
        explanation = row["explanation"]
        generatedAt = row["generated_at"]
    }
}
