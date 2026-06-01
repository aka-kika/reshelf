import Foundation
import GRDB

struct GraphLayoutCacheRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "graph_layout_cache"

    var id: String { focusRepositoryID }

    var focusRepositoryID: String
    var cacheKey: String
    var layoutJSON: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case focusRepositoryID = "focus_repository_id"
        case cacheKey = "cache_key"
        case layoutJSON = "layout_json"
        case createdAt = "created_at"
    }
}

struct GraphNodePosition: Codable, Equatable {
    var x: Double
    var y: Double
}

struct GraphLayoutSnapshot: Codable, Equatable {
    var cacheKey: String
    var positions: [String: GraphNodePosition]
}

struct GraphNeighborhood: Equatable {
    var focusRepositoryID: String
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var ecosystemNames: [String]
}

struct GraphFocusCandidate: Identifiable, Equatable {
    var id: String
    var fullName: String
    var relationshipCount: Int
}

struct GraphFilterState: Equatable, Codable {
    var enabledRelationshipTypes: Set<String> = []
    var minConfidence: Double = 0.35
    var ecosystemName: String?
    var localFirstOnly: Bool = false
    var mcpCompatibleOnly: Bool = false
    var clonedOnly: Bool = false
    var aiToolingOnly: Bool = false
    var desktopToolingOnly: Bool = false
    var includeSecondHop: Bool = true

    static let defaultRelationshipTypes: [String] = [
        "similar_to",
        "alternative_to",
        "integrates_with",
        "useful_for",
        "same_stack",
        "compatible_with",
        "same_problem_space"
    ]
}

struct GraphPathStep: Identifiable, Equatable, Codable {
    var edgeID: String
    var fromNodeID: String
    var toNodeID: String
    var fromLabel: String
    var toLabel: String
    var relationshipType: String
    var confidence: Double
    var evidenceText: String?

    var id: String { edgeID }
}

struct GraphPathResult: Equatable, Codable {
    var fromNodeID: String
    var toNodeID: String
    var fromLabel: String
    var toLabel: String
    var steps: [GraphPathStep]
    var hopCount: Int
    var explanation: String
}

struct GraphNavigationEntry: Equatable, Codable {
    var focusRepositoryID: String
    var selectedNodeID: String?
    var searchQuery: String?
    var filters: GraphFilterState
}

struct GraphNavigationSnapshot: Equatable, Codable {
    var recentSearches: [String]
    var recentFocusRepositoryIDs: [String]
    var trail: [GraphNavigationEntry]
}

struct GraphPathCacheRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "graph_path_cache"

    var id: String { cacheKey }

    var cacheKey: String
    var pathJSON: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case cacheKey = "cache_key"
        case pathJSON = "path_json"
        case createdAt = "created_at"
    }
}

struct GraphNavigationCacheRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "graph_navigation_cache"

    var id: String { cacheID }

    var cacheID: String
    var payloadJSON: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case cacheID = "cache_id"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }
}
