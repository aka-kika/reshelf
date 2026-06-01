import Foundation
import GRDB

struct GraphEdge: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "graph_edges"

    var id: String
    var sourceNodeID: String
    var targetNodeID: String
    var relationshipType: String
    var confidence: Double
    var evidenceText: String?
    var evidencePath: String?
    var createdBy: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sourceNodeID = "source_node_id"
        case targetNodeID = "target_node_id"
        case relationshipType = "relationship_type"
        case confidence
        case evidenceText = "evidence_text"
        case evidencePath = "evidence_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct GraphRelationshipSummary: Identifiable, Equatable {
    var id: String
    var relationshipType: String
    var targetType: String
    var targetKey: String
    var targetLabel: String
    var confidence: Double
    var evidenceText: String?
    var evidencePath: String?
    var createdBy: String

    init(id: String,
         relationshipType: String,
         targetType: String,
         targetKey: String,
         targetLabel: String,
         confidence: Double,
         evidenceText: String?,
         evidencePath: String?,
         createdBy: String) {
        self.id = id
        self.relationshipType = relationshipType
        self.targetType = targetType
        self.targetKey = targetKey
        self.targetLabel = targetLabel
        self.confidence = confidence
        self.evidenceText = evidenceText
        self.evidencePath = evidencePath
        self.createdBy = createdBy
    }

    init(row: Row) {
        id = row["id"]
        relationshipType = row["relationship_type"]
        targetType = row["target_type"]
        targetKey = row["target_key"]
        targetLabel = row["target_label"]
        confidence = row["confidence"]
        evidenceText = row["evidence_text"]
        evidencePath = row["evidence_path"]
        createdBy = row["created_by"]
    }
}

struct GraphRecommendationSignal: Identifiable, Equatable {
    var id: String
    var targetNodeID: String
    var targetType: String
    var targetKey: String
    var targetLabel: String
    var relationshipType: String
    var confidence: Double
    var evidenceText: String?
    var evidencePath: String?
    var createdBy: String

    init(row: Row) {
        id = row["id"]
        targetNodeID = row["target_node_id"]
        targetType = row["target_type"]
        targetKey = row["target_key"]
        targetLabel = row["target_label"]
        relationshipType = row["relationship_type"]
        confidence = row["confidence"]
        evidenceText = row["evidence_text"]
        evidencePath = row["evidence_path"]
        createdBy = row["created_by"]
    }
}
