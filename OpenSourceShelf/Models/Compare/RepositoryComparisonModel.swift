import Foundation
import GRDB

struct RepositoryComparisonProfile: Identifiable, Equatable, Codable {
    var id: String { repositoryID }
    var repositoryID: String
    var fullName: String
    var description: String?
    var primaryLanguage: String?
    var stars: Int?
    var licenseSPDX: String?
    var summary: String?
    var usefulness: String?
    var risks: [String]
    var classifications: [String]
    var stackItems: [String]
    var stackByCategory: [String: [String]]
    var setupComplexity: Int?
    var localFirstScore: Int?
    var experimentationPriority: Int?
    var ecosystemInfluence: Int?
    var personalRelevance: Int?
    var ecosystemNames: [String]
    var graphCentrality: Int
    var cloneStatus: String?
    var lastAnalyzedAt: String?
    var relationshipCount: Int
    var recommendationCount: Int
    var hasMCP: Bool
    var hasAIIntegration: Bool
    var productionReadiness: String
}

struct ComparisonRankingEntry: Identifiable, Equatable, Codable {
    var id: String { repositoryID }
    var repositoryID: String
    var fullName: String
    var rank: Int
    var compositeScore: Double
    var strongestSignals: [String]
    var weakestSignals: [String]
    var explanation: String
}

struct ComparisonPairPath: Identifiable, Equatable, Codable {
    var id: String { "\(fromRepositoryID)|\(toRepositoryID)" }
    var fromRepositoryID: String
    var toRepositoryID: String
    var fromLabel: String
    var toLabel: String
    var hopCount: Int
    var explanation: String
}

struct ComparisonGraphOverlap: Equatable, Codable {
    var sharedNeighbors: [String]
    var pairPaths: [ComparisonPairPath]
    var sharedIntegrations: [String]
    var alternativeLinks: [String]
}

struct ComparisonDecisionLine: Identifiable, Equatable, Codable {
    var id: String { category + winnerRepositoryID }
    var category: String
    var winnerRepositoryID: String
    var winnerLabel: String
    var explanation: String
}

struct ComparisonMatrixRow: Identifiable, Equatable, Codable {
    var id: String { key }
    var key: String
    var label: String
    var values: [String: String]
}

struct RepositoryComparisonResult: Equatable, Codable {
    var profiles: [RepositoryComparisonProfile]
    var rankings: [ComparisonRankingEntry]
    var sharedStack: [String]
    var uniqueStack: [String: [String]]
    var sharedEcosystems: [String]
    var uniqueRisks: [String: [String]]
    var uniqueStrengths: [String: [String]]
    var graphOverlap: ComparisonGraphOverlap
    var decisionSummary: [ComparisonDecisionLine]
    var matrixRows: [ComparisonMatrixRow]
    var cacheSignature: String
    var generatedAt: String
}

struct ComparisonSessionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "comparison_sessions"

    var id: String
    var repositoryIDsJSON: String
    var title: String?
    var isFavorite: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryIDsJSON = "repository_ids_json"
        case title
        case isFavorite = "is_favorite"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ComparisonResultsCacheRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "comparison_results_cache"

    var id: String { cacheSignature }

    var cacheSignature: String
    var repositoryIDsJSON: String
    var resultJSON: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case cacheSignature = "cache_signature"
        case repositoryIDsJSON = "repository_ids_json"
        case resultJSON = "result_json"
        case createdAt = "created_at"
    }
}

struct CompareDeepLinkRequest: Equatable, Codable {
    enum Intent: Equatable, Codable {
        case compare(repositoryIDs: [String])
        case addRepository(String)
        case compareSimilar(sourceRepositoryID: String)
        case compareAlternatives(sourceRepositoryID: String)
    }

    var intent: Intent
}

enum CompareDeepLinkNotifier {
    static let notificationName = Notification.Name("openCompareDeepLink")
    private static let payloadKey = "compareDeepLinkRequest"

    static func post(_ request: CompareDeepLinkRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        NotificationCenter.default.post(name: notificationName,
                                        object: nil,
                                        userInfo: [payloadKey: data])
    }

    static func decode(from notification: Notification) -> CompareDeepLinkRequest? {
        guard let data = notification.userInfo?[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(CompareDeepLinkRequest.self, from: data)
    }
}

struct CompareFocusCandidate: Identifiable, Equatable {
    var id: String
    var fullName: String
    var relationshipCount: Int
}
