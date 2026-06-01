import Foundation

enum CatalogRunbookFilter: String, CaseIterable, Identifiable {
    case all = "All Projects"
    case needsRunbook = "Needs Runbook"
    case staleRunbooks = "Stale Runbooks"
    case freshRunbooks = "Fresh Runbooks"
    case generatingRunbooks = "Generating Runbooks"
    case noIntelligence = "No Intelligence"

    var id: String { rawValue }

    func matches(_ state: CatalogIntelligenceState) -> Bool {
        switch self {
        case .all:
            return true
        case .needsRunbook:
            return state.matchesNeedsRunbook
        case .staleRunbooks:
            return state.runbookBadge == .staleRunbook
        case .freshRunbooks:
            return state.runbookBadge == .freshRunbook
        case .generatingRunbooks:
            return state.runbookBadge == .generating
        case .noIntelligence:
            return !state.hasIntelligence
        }
    }
}
