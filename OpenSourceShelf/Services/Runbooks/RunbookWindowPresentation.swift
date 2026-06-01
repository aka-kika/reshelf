import Combine
import Foundation

extension Notification.Name {
    static let openRunbookWindow = Notification.Name("openRunbookWindow")
}

/// Shared state for the dedicated Runbook window (which repository to show).
@MainActor
final class RunbookWindowState: ObservableObject {
    @Published var repositoryID: String?
}

enum RunbookWindowPresenter {
    static let repositoryIDKey = "repositoryID"

    static func present(repositoryID: String) {
        NotificationCenter.default.post(
            name: .openRunbookWindow,
            object: nil,
            userInfo: [repositoryIDKey: repositoryID]
        )
    }
}
