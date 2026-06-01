import Foundation

enum AppStatusBannerKind: Equatable {
    case runbookGenerated
    case runbookExported
    case batchRunbooksQueued
    case comparisonCreated
    case intelligenceRefreshComplete
}

struct AppStatusBanner: Equatable, Identifiable {
    var id: String { kindID + (repositoryID ?? "") }
    var kind: AppStatusBannerKind
    var title: String
    var repositoryID: String?
    var repositoryName: String?
    var detail: String?

    private var kindID: String {
        switch kind {
        case .runbookGenerated: return "runbookGenerated"
        case .runbookExported: return "runbookExported"
        case .batchRunbooksQueued: return "batchRunbooksQueued"
        case .comparisonCreated: return "comparisonCreated"
        case .intelligenceRefreshComplete: return "intelligenceRefreshComplete"
        }
    }
}

@MainActor
final class AppRefreshStore: ObservableObject {
    @Published private(set) var catalogRevision: UInt = 0
    @Published private(set) var queueRevision: UInt = 0
    @Published private(set) var compareRevision: UInt = 0
    @Published private(set) var ecosystemRevision: UInt = 0
    @Published private(set) var runbookRevisionByRepositoryID: [String: UInt] = [:]
    @Published private(set) var intelligenceRevisionByRepositoryID: [String: UInt] = [:]

    @Published var statusBanner: AppStatusBanner?

    private var catalogDebounceTask: Task<Void, Never>?

    func runbookRevision(for repositoryID: String?) -> UInt {
        guard let repositoryID else { return catalogRevision }
        return runbookRevisionByRepositoryID[repositoryID] ?? 0
    }

    func intelligenceRevision(for repositoryID: String?) -> UInt {
        guard let repositoryID else { return catalogRevision }
        return intelligenceRevisionByRepositoryID[repositoryID] ?? 0
    }

    func handle(_ event: AppRefreshEvent, database: IntelligenceDatabase = .shared) {
        switch event {
        case let .repositoryUpdated(repositoryID):
            bumpIntelligence(repositoryID)
            scheduleCatalogRefresh()

        case let .intelligenceUpdated(repositoryID):
            bumpIntelligence(repositoryID)
            queueRevision &+= 1
            scheduleCatalogRefresh()

        case .queueUpdated:
            queueRevision &+= 1

        case let .runbookUpdated(repositoryID):
            bumpRunbook(repositoryID)
            scheduleCatalogRefresh()

        case let .runbookGenerated(repositoryID):
            bumpRunbook(repositoryID)
            queueRevision &+= 1
            scheduleCatalogRefresh(immediate: true)
            if let banner = Self.banner(for: .runbookGenerated(repositoryID: repositoryID), database: database) {
                statusBanner = banner
            }

        case let .runbookExported(repositoryID, exportedCount):
            bumpRunbook(repositoryID)
            scheduleCatalogRefresh()
            statusBanner = AppStatusBanner(
                kind: .runbookExported,
                title: exportedCount == 1 ? "Runbook exported" : "\(exportedCount) runbooks exported",
                repositoryID: repositoryID,
                repositoryName: repositoryID.flatMap { try? database.fetchRepository(id: $0)?.fullName }
            )

        case let .batchRunbooksQueued(started, skipped):
            queueRevision &+= 1
            scheduleCatalogRefresh(immediate: true)
            guard started > 0 else { return }
            var detail: String?
            if skipped > 0 { detail = "\(skipped) skipped" }
            statusBanner = AppStatusBanner(
                kind: .batchRunbooksQueued,
                title: "\(started) runbook\(started == 1 ? "" : "s") queued",
                repositoryID: nil,
                repositoryName: nil,
                detail: detail
            )

        case .comparisonUpdated:
            compareRevision &+= 1
            statusBanner = AppStatusBanner(
                kind: .comparisonCreated,
                title: "Comparison ready",
                repositoryID: nil,
                repositoryName: nil,
                detail: "Review rankings and export the summary."
            )

        case .ecosystemUpdated:
            ecosystemRevision &+= 1

        case .catalogStateUpdated:
            scheduleCatalogRefresh(immediate: true)
        }
    }

    func showIntelligenceRefreshComplete(started: Int) {
        guard started > 0 else { return }
        statusBanner = AppStatusBanner(
            kind: .intelligenceRefreshComplete,
            title: "Intelligence refresh queued",
            repositoryID: nil,
            repositoryName: nil,
            detail: "\(started) repo\(started == 1 ? "" : "s") — track progress in Queue."
        )
        queueRevision &+= 1
        scheduleCatalogRefresh()
    }

    func dismissBanner() {
        statusBanner = nil
    }

    private func bumpRunbook(_ repositoryID: String?) {
        guard let repositoryID else { return }
        let next = (runbookRevisionByRepositoryID[repositoryID] ?? 0) &+ 1
        runbookRevisionByRepositoryID[repositoryID] = next
    }

    private func bumpIntelligence(_ repositoryID: String?) {
        guard let repositoryID else { return }
        let next = (intelligenceRevisionByRepositoryID[repositoryID] ?? 0) &+ 1
        intelligenceRevisionByRepositoryID[repositoryID] = next
    }

    private func scheduleCatalogRefresh(immediate: Bool = false) {
        catalogDebounceTask?.cancel()
        if immediate {
            catalogRevision &+= 1
            return
        }
        catalogDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            catalogRevision &+= 1
        }
    }

    private static func banner(for event: AppRefreshEvent,
                               database: IntelligenceDatabase) -> AppStatusBanner? {
        switch event {
        case let .runbookGenerated(repositoryID):
            let name = (try? database.fetchRepository(id: repositoryID))?.fullName ?? repositoryID
            return AppStatusBanner(kind: .runbookGenerated,
                                   title: "Runbook generated for \(name)",
                                   repositoryID: repositoryID,
                                   repositoryName: name)
        default:
            return nil
        }
    }
}
