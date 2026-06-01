import Foundation

/// Single list selection in the catalog.
enum CatalogListSelection: Equatable {
    case project(UUID)

    var projectID: UUID? {
        if case let .project(id) = self { return id }
        return nil
    }
}
