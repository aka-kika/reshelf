import Foundation
import SwiftData

/// Async work must not keep using a captured `ToolProject` across an await:
/// the user can delete the row meanwhile, and touching a deleted model is a
/// fatal SwiftData error. Capture the id before awaiting, then look the row up
/// again here (same pattern as `IconFetcher`).
enum LiveProject {
    /// The row with `id`, or nil once it is deleted (saved or not yet saved).
    @MainActor
    static func fetch(_ id: UUID, in context: ModelContext) -> ToolProject? {
        var descriptor = FetchDescriptor<ToolProject>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// False for a model that was deleted, so a caller holding an older list of
    /// rows can skip it before reading any of its fields.
    @MainActor
    static func isAlive(_ project: ToolProject) -> Bool {
        project.modelContext != nil && !project.isDeleted
    }
}
