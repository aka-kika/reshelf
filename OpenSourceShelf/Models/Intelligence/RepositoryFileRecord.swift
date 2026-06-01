import Foundation
import GRDB

struct RepositoryFileRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "repository_files"

    var id: String
    var repositoryID: String
    var path: String
    var fileType: String
    var category: String
    var sizeBytes: Int64?
    var detectedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case path
        case fileType = "file_type"
        case category
        case sizeBytes = "size_bytes"
        case detectedAt = "detected_at"
    }
}
