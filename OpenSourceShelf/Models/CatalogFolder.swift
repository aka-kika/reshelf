import Foundation
import SwiftData

/// A grouping the user makes — "everything I cloned for project X".
///
/// Deliberately *not* a category (those are a fixed taxonomy describing what a
/// repo is) and not a shelf (that says how much you value it). A project belongs
/// to at most one folder, and a folder holds any project whether or not it's
/// cloned — uncloning must not eject a repo from the group that exists to make
/// the cleanup possible.
@Model
final class CatalogFolder {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    /// Manual ordering in the sidebar. Ties break on name.
    var sortIndex: Int = 0

    init(name: String, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.sortIndex = sortIndex
    }
}
