import Foundation

struct RunbookDeepLinkRequest: Equatable, Codable {
    var repositoryID: String
    /// Opens the dedicated runbook window (replaces inspector scroll focus).
    var openInWindow: Bool = true

    private enum CodingKeys: String, CodingKey {
        case repositoryID
        case openInWindow
        case scrollToRunbook
    }

    init(repositoryID: String, openInWindow: Bool = true) {
        self.repositoryID = repositoryID
        self.openInWindow = openInWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryID = try container.decode(String.self, forKey: .repositoryID)
        if let openInWindow = try container.decodeIfPresent(Bool.self, forKey: .openInWindow) {
            self.openInWindow = openInWindow
        } else if let scrollToRunbook = try container.decodeIfPresent(Bool.self, forKey: .scrollToRunbook) {
            openInWindow = scrollToRunbook
        } else {
            openInWindow = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(repositoryID, forKey: .repositoryID)
        try container.encode(openInWindow, forKey: .openInWindow)
    }
}

enum RunbookDeepLinkNotifier {
    static let notificationName = Notification.Name("openRunbookDeepLink")
    private static let payloadKey = "runbookDeepLinkRequest"

    static func post(_ request: RunbookDeepLinkRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        NotificationCenter.default.post(name: notificationName,
                                        object: nil,
                                        userInfo: [payloadKey: data])
    }

    static func decode(from notification: Notification) -> RunbookDeepLinkRequest? {
        guard let data = notification.userInfo?[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(RunbookDeepLinkRequest.self, from: data)
    }
}
