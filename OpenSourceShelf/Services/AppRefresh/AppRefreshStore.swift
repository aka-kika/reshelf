import Foundation

/// Turns refresh-bus events into one observable counter. Views watch
/// `catalogRevision` and re-read when it bumps.
@MainActor
final class AppRefreshStore: ObservableObject {
    @Published private(set) var catalogRevision: UInt = 0

    func handle(_ event: AppRefreshEvent) {
        switch event {
        case .catalogStateUpdated:
            catalogRevision &+= 1
        }
    }
}
