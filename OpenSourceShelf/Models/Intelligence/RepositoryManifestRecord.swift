import Foundation
import GRDB

struct RepositoryManifestRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "repository_manifests"

    var id: String
    var repositoryID: String
    var path: String
    var type: String
    var ecosystem: String
    var evidenceText: String?
    var detectedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case path
        case type
        case ecosystem
        case evidenceText = "evidence_text"
        case detectedAt = "detected_at"
    }
}
