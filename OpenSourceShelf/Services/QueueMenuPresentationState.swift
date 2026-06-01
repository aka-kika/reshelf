import Foundation
import SwiftUI

@MainActor
final class QueueMenuPresentationState: ObservableObject {
    func present() {
        NotificationCenter.default.post(name: .openQueue, object: nil)
    }
}

struct QueueMenuBarRoot: View {
    @ObservedObject var viewModel: QueueViewModel
    @EnvironmentObject private var appRefreshStore: AppRefreshStore

    var body: some View {
        QueueView(viewModel: viewModel)
            .onAppear {
                viewModel.startPolling()
            }
            .onDisappear {
                viewModel.stopPolling()
            }
            .onChange(of: appRefreshStore.queueRevision) { _, _ in
                viewModel.reload()
            }
    }
}
