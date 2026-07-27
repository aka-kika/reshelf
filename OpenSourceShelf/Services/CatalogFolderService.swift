import Foundation
import SwiftData

/// Every folder mutation goes through here.
///
/// The rule that matters: `delete` clears membership and removes the folder. It
/// must never touch a project's shelf, clone, notes or anything else. Deleting a
/// container does not delete its contents.
enum CatalogFolderService {

    static func folders(in context: ModelContext) -> [CatalogFolder] {
        let all = (try? context.fetch(FetchDescriptor<CatalogFolder>())) ?? []
        return all.sorted {
            $0.sortIndex == $1.sortIndex
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.sortIndex < $1.sortIndex
        }
    }

    /// Creates a folder, or returns the existing one when the name is already
    /// taken — case-insensitively, so "Photos" and "photos" are one folder.
    /// Returns nil for a blank name.
    @discardableResult
    static func create(name: String, in context: ModelContext) -> CatalogFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = folders(in: context).first(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return existing
        }
        let next = (folders(in: context).map(\.sortIndex).max() ?? -1) + 1
        let folder = CatalogFolder(name: trimmed, sortIndex: next)
        context.insert(folder)
        try? context.save()
        return folder
    }

    static func rename(_ folder: CatalogFolder, to name: String, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        try? context.save()
    }

    /// Removes the folder and clears membership. Returns how many projects were
    /// ungrouped, so the caller can say so before and after.
    @discardableResult
    static func delete(_ folder: CatalogFolder, in context: ModelContext) -> Int {
        let members = projects(in: folder, context: context)
        for project in members {
            project.folderID = nil          // and nothing else
        }
        context.delete(folder)
        try? context.save()
        return members.count
    }

    /// Pass nil to remove a project from whatever folder it's in.
    static func assign(_ project: ToolProject, to folder: CatalogFolder?, in context: ModelContext) {
        project.folderID = folder?.id
        try? context.save()
    }

    /// Bulk assign — one save for the whole batch rather than one per project.
    static func assign(_ projects: [ToolProject], to folder: CatalogFolder?, in context: ModelContext) {
        for project in projects {
            project.folderID = folder?.id
        }
        try? context.save()
    }

    static func projects(in folder: CatalogFolder, context: ModelContext) -> [ToolProject] {
        let id = folder.id
        let descriptor = FetchDescriptor<ToolProject>(
            predicate: #Predicate { $0.folderID == id },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func projectCount(for folder: CatalogFolder, in context: ModelContext) -> Int {
        let id = folder.id
        let descriptor = FetchDescriptor<ToolProject>(predicate: #Predicate { $0.folderID == id })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func folder(withID id: UUID, in context: ModelContext) -> CatalogFolder? {
        folders(in: context).first { $0.id == id }
    }
}
