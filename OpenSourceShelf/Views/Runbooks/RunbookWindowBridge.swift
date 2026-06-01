import SwiftUI

/// Opens the Runbook window when a repository runbook should be shown.
struct RunbookWindowBridge: View {
    @EnvironmentObject private var runbookWindowState: RunbookWindowState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .openRunbookWindow)) { notification in
                guard let repositoryID = notification.userInfo?[RunbookWindowPresenter.repositoryIDKey] as? String else {
                    return
                }
                runbookWindowState.repositoryID = repositoryID
                openWindow(id: ShelfWindowID.runbook)
            }
    }
}
