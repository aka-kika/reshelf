import Foundation

enum AppRefreshBus {
    static let notificationName = Notification.Name("AppRefreshEvent")

    static func emit(_ event: AppRefreshEvent) {
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: event.userInfo)

        switch event {
        case let .runbookGenerated(repositoryID):
            NotificationCenter.default.post(name: .runbookGenerationDidComplete,
                                            object: nil,
                                            userInfo: ["repositoryID": repositoryID])
        case .queueUpdated:
            NotificationCenter.default.post(name: .openQueueRefresh, object: nil)
        default:
            break
        }
    }
}

extension Notification.Name {
    static let openQueueRefresh = Notification.Name("openQueueRefresh")
}
