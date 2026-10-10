import Foundation

/// Typed events on the refresh bus. Only the catalog event is left: the
/// queue, runbook, comparison and ecosystem events went with the v2 surfaces
/// that sent and received them. Add a case here (plus its `decode` arm) when a
/// new cross-surface refresh is needed.
enum AppRefreshEvent: Equatable {
    /// Something in the catalog changed (a save, a clone, a shelf move) —
    /// badges and the inspector re-read.
    case catalogStateUpdated

    var eventName: String {
        switch self {
        case .catalogStateUpdated: return "catalogStateUpdated"
        }
    }

    var userInfo: [String: Any] {
        ["event": eventName]
    }

    static func decode(from notification: Notification) -> AppRefreshEvent? {
        switch notification.userInfo?["event"] as? String {
        case "catalogStateUpdated": return .catalogStateUpdated
        default: return nil
        }
    }
}
