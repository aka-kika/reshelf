import Foundation

enum AppQuickAction: String {
    case generateRunbook
    case regenerateStaleRunbooks
    case showNeedsRunbook
    case showStaleRunbooks
    case openQueue
    case openRunbook
    case compareSelected
    case openCompare
    case openEcosystems
    case openMyStack
    case refreshIntelligence
}

enum AppQuickActionCenter {
    static let notificationName = Notification.Name("AppQuickAction")
    static let catalogActionName = Notification.Name("AppCatalogQuickAction")

    static func post(_ action: AppQuickAction) {
        NotificationCenter.default.post(name: notificationName,
                                        object: nil,
                                        userInfo: ["action": action.rawValue])
    }

    static func postCatalog(_ action: AppQuickAction) {
        NotificationCenter.default.post(name: catalogActionName,
                                        object: nil,
                                        userInfo: ["action": action.rawValue])
    }
}

extension Notification.Name {
    static let setCatalogRunbookFilter = Notification.Name("setCatalogRunbookFilter")
}
