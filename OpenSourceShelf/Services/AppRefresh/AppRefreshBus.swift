import Foundation

enum AppRefreshBus {
    static let notificationName = Notification.Name("AppRefreshEvent")

    /// Broadcasts a refresh event. The runbook and queue fan-out that used to
    /// live here went with the v2 surfaces that listened for it.
    static func emit(_ event: AppRefreshEvent) {
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: event.userInfo)
    }
}
