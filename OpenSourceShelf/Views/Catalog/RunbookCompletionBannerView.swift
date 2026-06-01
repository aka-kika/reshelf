import SwiftUI

struct AppStatusBannerView: View {
    @ObservedObject var refreshStore: AppRefreshStore

    var body: some View {
        if let banner = refreshStore.statusBanner {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: banner.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor(for: banner.kind))
                VStack(alignment: .leading, spacing: 1) {
                    Text(banner.title)
                        .font(.system(size: 12))
                    if let detail = banner.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ForEach(primaryActions(for: banner), id: \.title) { action in
                    Button(action.title) {
                        action.handler()
                        refreshStore.dismissBanner()
                    }
                    .controlSize(.small)
                }
                Button("Dismiss") {
                    refreshStore.dismissBanner()
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
        }
    }

    private struct BannerAction {
        var title: String
        var handler: () -> Void
    }

    private func primaryActions(for banner: AppStatusBanner) -> [BannerAction] {
        switch banner.kind {
        case .runbookGenerated, .runbookExported:
            guard let repositoryID = banner.repositoryID else { return [] }
            return [BannerAction(title: "Open Runbook") {
                RunbookDeepLinkNotifier.post(
                    RunbookDeepLinkRequest(repositoryID: repositoryID)
                )
            }]
        case .batchRunbooksQueued, .intelligenceRefreshComplete:
            return [BannerAction(title: "Open Queue") {
                NotificationCenter.default.post(name: .openQueue, object: nil)
            }]
        case .comparisonCreated:
            return [BannerAction(title: "Open Compare") {
                NotificationCenter.default.post(name: .openCompare, object: nil)
            }]
        }
    }

    private func iconName(for kind: AppStatusBannerKind) -> String {
        switch kind {
        case .runbookGenerated, .runbookExported: return "doc.text"
        case .batchRunbooksQueued, .intelligenceRefreshComplete: return "tray.full"
        case .comparisonCreated: return "arrow.left.arrow.right"
        }
    }

    private func iconColor(for kind: AppStatusBannerKind) -> Color {
        switch kind {
        case .runbookGenerated, .runbookExported: return .green
        case .batchRunbooksQueued, .intelligenceRefreshComplete: return .blue
        case .comparisonCreated: return .accentColor
        }
    }
}

// Legacy alias — prefer AppRefreshStore directly.
typealias RunbookCompletionBannerModel = AppRefreshStore

enum RunbookCompletionBannerNotifier {
    static func handleCompletion(repositoryID: String, database: IntelligenceDatabase = .shared) -> AppStatusBanner? {
        guard let repository = try? database.fetchRepository(id: repositoryID) else { return nil }
        return AppStatusBanner(kind: .runbookGenerated,
                               title: "Runbook generated for \(repository.fullName)",
                               repositoryID: repositoryID,
                               repositoryName: repository.fullName)
    }
}

extension Notification.Name {
    static let openCompare = Notification.Name("openCompare")
    static let openEcosystems = Notification.Name("openEcosystems")
    static let openMyStack = Notification.Name("openMyStack")
}
