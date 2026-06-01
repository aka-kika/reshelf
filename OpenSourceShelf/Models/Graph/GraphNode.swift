import Foundation
import GRDB

struct GraphNode: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "graph_nodes"

    var id: String
    var type: String
    var key: String
    var label: String
    var metadataJSON: String

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case key
        case label
        case metadataJSON = "metadata_json"
    }
}
