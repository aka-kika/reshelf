import Foundation
import GRDB

struct RepositoryRunbookRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "repository_runbooks"

    var id: String
    var repositoryID: String
    var title: String
    var summary: String?
    var markdown: String
    var evidenceSignature: String
    var generatedBy: String
    var modelName: String?
    var promptVersion: String?
    var evidenceComponentsJSON: String?
    var lastExportedAt: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case repositoryID = "repository_id"
        case title
        case summary
        case markdown
        case evidenceSignature = "evidence_signature"
        case generatedBy = "generated_by"
        case modelName = "model_name"
        case promptVersion = "prompt_version"
        case evidenceComponentsJSON = "evidence_components_json"
        case lastExportedAt = "last_exported_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isAIAssisted: Bool {
        generatedBy == "ollama"
    }
}
