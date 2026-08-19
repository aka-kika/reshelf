import Foundation

enum AppRefreshBus {
    static let notificationName = Notification.Name("AppRefreshEvent")

    /// Broadcasts a refresh event. The runbook and queue fan-out that used to
    /// live here went with the v2 surfaces that listened for it.
    ///
    /// Always posts on the main thread: NotificationCenter publishers deliver
    /// on the posting thread, and the receivers mutate @Published state. The
    /// ingestion services emit from the cooperative pool, which published from
    /// a background thread — the intermittent stuck UI through 1.10.0.
    static func emit(_ event: AppRefreshEvent) {
        let userInfo = event.userInfo
        if Thread.isMainThread {
            NotificationCenter.default.post(name: notificationName, object: nil, userInfo: userInfo)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: notificationName, object: nil, userInfo: userInfo)
            }
        }
    }
}
