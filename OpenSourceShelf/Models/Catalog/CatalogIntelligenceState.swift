import Foundation

enum CatalogRunbookBadge: String, Equatable, CaseIterable {
    case noIntelligence = "No Intelligence"
    case generating = "Generating"
    case neverGenerated = "Never Generated"
    case freshRunbook = "Fresh Runbook"
    case staleRunbook = "Stale Runbook"

    var sortOrder: Int {
        switch self {
        case .generating: return 0
        case .noIntelligence: return 1
        case .staleRunbook: return 2
        case .neverGenerated: return 3
        case .freshRunbook: return 4
        }
    }
}

struct CatalogIntelligenceState: Equatable, Identifiable {
    var projectID: UUID
    var repositoryID: String?
    var hasIntelligence: Bool
    var cloneStatus: String?
    var analysisStatus: CatalogIntelligenceStatus
    var runbookBadge: CatalogRunbookBadge
    var runbookFreshness: RunbookFreshnessState?
    var runbookLastGeneratedAt: String?
    var runbookLastExportedAt: String?
    var activeJobStatus: String?
    var staleReason: String?
    var analysisErrorMessage: String?

    var id: UUID { projectID }

    var matchesNeedsRunbook: Bool {
        hasIntelligence && (runbookBadge == .neverGenerated || runbookBadge == .staleRunbook)
    }

    var tooltipText: String {
        var lines: [String] = []
        lines.append(runbookBadge.rawValue)
        if let generated = runbookLastGeneratedAt {
            lines.append("Generated: \(CatalogIntelligenceState.formattedDate(generated))")
        }
        if let exported = runbookLastExportedAt {
            lines.append("Exported: \(CatalogIntelligenceState.formattedDate(exported))")
        }
        if let staleReason, !staleReason.isEmpty {
            lines.append(staleReason)
        }
        if let activeJobStatus {
            lines.append("Runbook job: \(activeJobStatus)")
        }
        if let analysisErrorMessage, !analysisErrorMessage.isEmpty {
            lines.append(analysisErrorMessage)
        }
        return lines.joined(separator: "\n")
    }

    /// Compact secondary line for catalog rows — nil when there is nothing useful to show.
    var compactMetadataLine: String? {
        guard hasIntelligence else { return nil }
        var parts: [String] = []
        if runbookLastGeneratedAt != nil {
            parts.append("Generated")
        }
        if runbookLastExportedAt != nil {
            parts.append("Exported")
        }
        if runbookBadge == .staleRunbook, let staleReason, !staleReason.isEmpty {
            let short = staleReason.count > 48 ? String(staleReason.prefix(45)) + "…" : staleReason
            parts.append("Stale: \(short)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    var intelligenceSnapshot: CatalogIntelligenceStatusSnapshot {
        CatalogIntelligenceStatusSnapshot(status: analysisStatus,
                                          errorMessage: analysisErrorMessage,
                                          repositoryID: repositoryID)
    }

    static func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso
    }
}
