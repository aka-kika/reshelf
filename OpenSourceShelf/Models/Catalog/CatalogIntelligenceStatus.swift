import SwiftUI

enum CatalogIntelligenceStatus: String, Equatable, CaseIterable {
    case notFetched = "Not fetched"
    case queued = "Queued"
    case fetching = "Fetching"
    case cloning = "Cloning"
    case analyzing = "Analyzing"
    case ready = "Ready"
    case failed = "Failed"

    var icon: String {
        switch self {
        case .notFetched:
            return "sparkles"
        case .queued:
            return "clock"
        case .fetching:
            return "arrow.down.circle"
        case .cloning:
            return "externaldrive"
        case .analyzing:
            return "waveform.path.ecg"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notFetched:
            return .secondary
        case .queued:
            return .orange
        case .fetching, .cloning, .analyzing:
            return .blue
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }

    var canFetch: Bool {
        switch self {
        case .notFetched, .failed:
            return true
        case .queued, .fetching, .cloning, .analyzing, .ready:
            return false
        }
    }
}

struct CatalogIntelligenceStatusSnapshot: Equatable {
    var status: CatalogIntelligenceStatus
    var errorMessage: String?
    var repositoryID: String?

    static let notFetched = CatalogIntelligenceStatusSnapshot(status: .notFetched,
                                                              errorMessage: nil,
                                                              repositoryID: nil)
}

enum CatalogIntelligenceFetchOutcome: Equatable {
    case started
    case skippedAlreadyReady
    case skippedInProgress
    case skippedInvalidURL
    case skippedNoGitHubURL
    case failed(String)

    var isSuccess: Bool {
        switch self {
        case .started, .skippedAlreadyReady, .skippedInProgress:
            return true
        case .skippedInvalidURL, .skippedNoGitHubURL, .failed:
            return false
        }
    }
}

enum CatalogCloneLocallyOutcome: Equatable {
    case succeeded
    case failed(String)
}

struct CatalogIntelligenceBatchResult: Equatable {
    var started: Int
    var skippedReady: Int
    var skippedInProgress: Int
    var skippedInvalid: Int
    var failed: Int

    var summaryMessage: String {
        var parts: [String] = []
        if started > 0 {
            parts.append("\(started) started")
        }
        let skippedTotal = skippedReady + skippedInProgress + skippedInvalid
        if skippedTotal > 0 {
            parts.append("\(skippedTotal) skipped")
        }
        if failed > 0 {
            parts.append("\(failed) failed")
        }
        if parts.isEmpty {
            return "No projects needed intelligence fetching."
        }
        return parts.joined(separator: ", ")
    }
}
