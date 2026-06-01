import SwiftUI

/// Opens the dedicated Queue window when `.openQueue` is posted (menu bar, ⌘⇧Q, banners).
struct QueueWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .openQueue)) { _ in
                openWindow(id: ShelfWindowID.queue)
            }
    }
}

enum ShelfWindowID {
    static let queue = "ingestion-queue"
    static let runbook = "runbook-viewer"
}
