import Foundation

enum AppRefreshEvent: Equatable {
    case repositoryUpdated(repositoryID: String?)
    case intelligenceUpdated(repositoryID: String?)
    case queueUpdated
    case runbookUpdated(repositoryID: String?)
    case runbookGenerated(repositoryID: String)
    case runbookExported(repositoryID: String?, exportedCount: Int)
    case batchRunbooksQueued(started: Int, skipped: Int)
    case comparisonUpdated
    case ecosystemUpdated
    case catalogStateUpdated

    var eventName: String {
        switch self {
        case .repositoryUpdated: return "repositoryUpdated"
        case .intelligenceUpdated: return "intelligenceUpdated"
        case .queueUpdated: return "queueUpdated"
        case .runbookUpdated: return "runbookUpdated"
        case .runbookGenerated: return "runbookGenerated"
        case .runbookExported: return "runbookExported"
        case .batchRunbooksQueued: return "batchRunbooksQueued"
        case .comparisonUpdated: return "comparisonUpdated"
        case .ecosystemUpdated: return "ecosystemUpdated"
        case .catalogStateUpdated: return "catalogStateUpdated"
        }
    }

    var repositoryID: String? {
        switch self {
        case let .repositoryUpdated(id),
             let .intelligenceUpdated(id),
             let .runbookUpdated(id),
             let .runbookExported(id, _):
            return id
        case let .runbookGenerated(id):
            return id
        default:
            return nil
        }
    }

    var userInfo: [String: Any] {
        var info: [String: Any] = ["event": eventName]
        switch self {
        case let .repositoryUpdated(id),
             let .intelligenceUpdated(id),
             let .runbookUpdated(id):
            if let id { info["repositoryID"] = id }
        case let .runbookGenerated(id):
            info["repositoryID"] = id
        case let .runbookExported(id, count):
            if let id { info["repositoryID"] = id }
            info["exportedCount"] = count
        case let .batchRunbooksQueued(started, skipped):
            info["started"] = started
            info["skipped"] = skipped
        case .comparisonUpdated, .queueUpdated, .ecosystemUpdated, .catalogStateUpdated:
            break
        }
        return info
    }

    static func decode(from notification: Notification) -> AppRefreshEvent? {
        guard let name = notification.userInfo?["event"] as? String else { return nil }
        let repositoryID = notification.userInfo?["repositoryID"] as? String

        switch name {
        case "repositoryUpdated":
            return .repositoryUpdated(repositoryID: repositoryID)
        case "intelligenceUpdated":
            return .intelligenceUpdated(repositoryID: repositoryID)
        case "queueUpdated":
            return .queueUpdated
        case "runbookUpdated":
            return .runbookUpdated(repositoryID: repositoryID)
        case "runbookGenerated":
            guard let repositoryID else { return nil }
            return .runbookGenerated(repositoryID: repositoryID)
        case "runbookExported":
            let count = notification.userInfo?["exportedCount"] as? Int ?? 1
            return .runbookExported(repositoryID: repositoryID, exportedCount: count)
        case "batchRunbooksQueued":
            let started = notification.userInfo?["started"] as? Int ?? 0
            let skipped = notification.userInfo?["skipped"] as? Int ?? 0
            return .batchRunbooksQueued(started: started, skipped: skipped)
        case "comparisonUpdated":
            return .comparisonUpdated
        case "ecosystemUpdated":
            return .ecosystemUpdated
        case "catalogStateUpdated":
            return .catalogStateUpdated
        default:
            return nil
        }
    }
}
