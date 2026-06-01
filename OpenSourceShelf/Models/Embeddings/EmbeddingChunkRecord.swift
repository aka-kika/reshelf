import Foundation
import GRDB

struct EmbeddingChunkRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "embedding_chunks"

    var id: String
    var repositoryID: String
    var sourceType: String
    var sourcePath: String
    var chunkText: String
    var contentHash: String
    var embeddingModel: String
    var embedding: Data
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case sourceType = "source_type"
        case sourcePath = "source_path"
        case chunkText = "chunk_text"
        case contentHash = "content_hash"
        case embeddingModel = "embedding_model"
        case embedding
        case createdAt = "created_at"
    }
}

struct EmbeddingChunkSummary: Identifiable, Equatable {
    var id: String
    var repositoryID: String
    var sourceType: String
    var sourcePath: String
    var chunkText: String
    var embeddingModel: String
    var embedding: Data

    init(row: Row) {
        id = row["id"]
        repositoryID = row["repository_id"]
        sourceType = row["source_type"]
        sourcePath = row["source_path"]
        chunkText = row["chunk_text"]
        embeddingModel = row["embedding_model"]
        embedding = row["embedding"]
    }
}
