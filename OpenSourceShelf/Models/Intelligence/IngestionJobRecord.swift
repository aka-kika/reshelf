import Foundation
import GRDB

struct IngestionJobRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "ingestion_jobs"

    var id: String
    var repositoryID: String?
    var type: String
    var status: String
    var priority: Int
    var progress: Double
    var error: String?
    var createdAt: String
    var startedAt: String?
    var completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case type
        case status
        case priority
        case progress
        case error
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}
