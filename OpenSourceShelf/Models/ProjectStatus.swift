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
