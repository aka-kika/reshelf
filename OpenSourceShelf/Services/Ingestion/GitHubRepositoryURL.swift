import Foundation

struct GitHubRepositoryURL: Equatable {
    let host: String
    let owner: String
    let name: String

    var fullName: String {
        "\(owner)/\(name)"
    }

    var canonicalURL: String {
        "https://\(host)/\(fullName)"
    }

    static func parse(_ rawValue: String) -> GitHubRepositoryURL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let sshParts = parseSCPStyleURL(trimmed) {
            return sshParts
        }

        let valueWithScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("ssh://") {
            valueWithScheme = trimmed
        } else {
            valueWithScheme = "https://\(trimmed)"
        }

        guard let components = URLComponents(string: valueWithScheme),
              let rawHost = components.host?.lowercased(),
              rawHost == "github.com" || rawHost == "www.github.com" else {
            return nil
        }

        let parts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard parts.count >= 2 else { return nil }
        return make(host: "github.com", owner: parts[0], repo: parts[1])
    }

    static func parseFullName(_ fullName: String) -> GitHubRepositoryURL? {
        let parts = fullName
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard parts.count == 2 else { return nil }
        return make(host: "github.com", owner: parts[0], repo: parts[1])
    }

    private static func parseSCPStyleURL(_ value: String) -> GitHubRepositoryURL? {
        guard value.hasPrefix("git@github.com:") else { return nil }
        let path = String(value.dropFirst("git@github.com:".count))
        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard parts.count >= 2 else { return nil }
        return make(host: "github.com", owner: parts[0], repo: parts[1])
    }

    private static func make(host: String, owner: String, repo: String) -> GitHubRepositoryURL? {
        let normalizedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var normalizedRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRepo.hasSuffix(".git") {
            normalizedRepo.removeLast(4)
        }

        guard isValidPathComponent(normalizedOwner),
              isValidPathComponent(normalizedRepo) else {
            return nil
        }

        return GitHubRepositoryURL(host: host, owner: normalizedOwner, name: normalizedRepo)
    }

    private static func isValidPathComponent(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.contains(" "),
              !value.contains(":") else {
            return false
        }
        return value.range(of: #"^[a-z0-9._-]+$"#, options: .regularExpression) != nil
    }
}
