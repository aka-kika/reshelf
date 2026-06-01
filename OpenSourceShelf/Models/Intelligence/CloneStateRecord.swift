import Foundation
import GRDB

struct CloneStateRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "clone_states"

    var repositoryID: String
    var status: String
    var cloneMode: String
    var path: String?
    var currentHead: String?
    var branchCount: Int?
    var tagCount: Int?
    var sizeBytes: Int64?
    var lastFetchAt: String?
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case repositoryID = "repository_id"
        case status
        case cloneMode = "clone_mode"
        case path
        case currentHead = "current_head"
        case branchCount = "branch_count"
        case tagCount = "tag_count"
        case sizeBytes = "size_bytes"
        case lastFetchAt = "last_fetch_at"
        case lastError = "last_error"
    }
}
