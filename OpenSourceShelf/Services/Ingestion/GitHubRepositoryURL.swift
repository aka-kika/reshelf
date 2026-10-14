import Foundation

/// The one place that reads a GitHub repo link. Everything else — capture,
/// duplicate detection, clone folders, the clone index, the metadata store —
/// asks this type instead of parsing links itself.
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

    /// Owner and repo from a link, in their original case (clone folders use
    /// it). Accepts `https://`, `http://`, `ssh://`, no scheme at all, `www.`,
    /// and `git@github.com:owner/repo`. Ignores `/tree/…` and `/blob/…`, a
    /// `?query` or `#anchor` after the repo, and a trailing `.git`.
    static func ownerAndRepo(from rawValue: String) -> (owner: String, repo: String)? {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("git@github.com:") {
            cleaned = "github.com/" + cleaned.dropFirst("git@github.com:".count)
        }
        for prefix in ["https://", "http://", "ssh://git@", "ssh://"] where cleaned.lowercased().hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count))
            break
        }
        if cleaned.lowercased().hasPrefix("www.") {
            cleaned = String(cleaned.dropFirst(4))
        }
        guard cleaned.lowercased().hasPrefix("github.com/") else { return nil }

        let parts = cleaned.dropFirst("github.com/".count)
            .split(separator: "/")
            .filter { !$0.isEmpty && $0 != "tree" && $0 != "blob" }
        guard parts.count >= 2 else { return nil }

        var repo = String(parts[1])
        if let cut = repo.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            repo = String(repo[..<cut])
        }
        if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        let owner = String(parts[0])
        // Only what GitHub itself allows in a name. A pasted link with spaces,
        // quotes or broken %-escapes would otherwise reach URL building and
        // folder paths, and `..` as a repo would point a clone at its parent.
        guard isGitHubName(owner), isGitHubName(repo) else { return nil }
        return (owner, repo)
    }

    private static func isGitHubName(_ value: String) -> Bool {
        guard value != ".", value != ".." else { return false }
        return value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    /// Lowercased, validated repo identity (the metadata store's key).
    static func parse(_ rawValue: String) -> GitHubRepositoryURL? {
        guard let (owner, repo) = ownerAndRepo(from: rawValue) else { return nil }
        return make(host: "github.com", owner: owner, repo: repo)
    }

    static func parseFullName(_ fullName: String) -> GitHubRepositoryURL? {
        let parts = fullName
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard parts.count == 2 else { return nil }
        return make(host: "github.com", owner: parts[0], repo: parts[1])
    }

    /// `owner/repo` lowercased — two links to the same repo give the same key
    /// (http/https, `www.`, trailing slash, `.git`, `/tree/…`, case). A
    /// non-GitHub link falls back to the trimmed, lowercased link.
    static func dedupKey(for url: String) -> String {
        if let (owner, repo) = ownerAndRepo(from: url) {
            return "\(owner)/\(repo)".lowercased()
        }
        return url.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
