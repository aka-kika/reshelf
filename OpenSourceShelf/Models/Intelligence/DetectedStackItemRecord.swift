import Foundation
import GRDB

struct DetectedStackItemRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "detected_stack_items"

    var id: String
    var repositoryID: String
    var name: String
    var category: String
    var detectionSource: String
    var confidence: Double
    var evidencePath: String?
    var evidenceText: String?
    var detectedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case name
        case category
        case detectionSource = "detection_source"
        case confidence
        case evidencePath = "evidence_path"
        case evidenceText = "evidence_text"
        case detectedAt = "detected_at"
    }
}
