import Foundation

/// What the project list is currently showing.
///
/// `SidebarItem` is a `String`-backed `CaseIterable` enum — a closed set, and
/// several menus are built from `allCases`. Folders are created at runtime, so
/// they cannot be cases of it. Wrapping both in one type keeps `SidebarItem`
/// closed while making it impossible for the app to hold two different answers
/// to "what is the list filtered by" at once.
enum ShelfSelection: Hashable {
    case builtin(SidebarItem)
    case folder(UUID)
    /// A GitHub topic from the sidebar's Tags section (`SidebarTagRanking.key`).
    case tag(String)

    var builtinItem: SidebarItem? {
        if case let .builtin(item) = self { return item }
        return nil
    }

    var folderID: UUID? {
        if case let .folder(id) = self { return id }
        return nil
    }

    var tagName: String? {
        if case let .tag(name) = self { return name }
        return nil
    }
}
