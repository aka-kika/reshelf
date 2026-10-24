import Foundation

/// Where a tool sits on your shelf. New captures land in `.collector` by default;
/// you optionally promote keepers to `.topShelf` or let duds go to `.yardSale`.
enum ProjectStatus: String, CaseIterable, Codable {
    case topShelf = "topShelf"     // the keepers / favorites
    case collector = "collector"   // your collection — default home for new captures
    case yardSale = "yardSale"     // letting it go / archived

    /// Where freshly captured repos start.
    static let defaultStatus: ProjectStatus = .collector

    var displayName: String {
        switch self {
        case .topShelf: "Top Shelf"
        case .collector: "The Collector"
        case .yardSale: "Yard Sale"
        }
    }

    var sfSymbol: String {
        switch self {
        case .topShelf: "star.fill"
        case .collector: "square.stack.3d.up"
        case .yardSale: "tag"
        }
    }
}

/// How a click changes the list's batch. A plain click is one row. The first
/// ⌘-click after that keeps the plain-clicked row in the batch, so the rows
/// that look selected are the rows a batch action (and ⌘T) will use.
enum CatalogBatchClick {
    struct State: Equatable {
        var batch: Set<UUID> = []
        var anchor: UUID?
        var selected: UUID?
    }

    static func apply(_ state: State, clicked: UUID, command: Bool, shift: Bool,
                      orderedIDs: [UUID]) -> State {
        var next = state
        if command {
            if next.batch.isEmpty, let current = next.selected, current != clicked {
                next.batch.insert(current)
                if next.anchor == nil { next.anchor = current }
            }
            if next.batch.contains(clicked) {
                next.batch.remove(clicked)
            } else {
                next.batch.insert(clicked)
                if next.anchor == nil { next.anchor = clicked }
            }
            return next
        }
        if shift, let anchor = next.anchor ?? next.selected,
           let from = orderedIDs.firstIndex(of: anchor),
           let to = orderedIDs.firstIndex(of: clicked) {
            next.batch.formUnion(orderedIDs[min(from, to)...max(from, to)])
            return next
        }
        next.batch.removeAll()
        next.anchor = clicked
        next.selected = clicked
        return next
    }
}
