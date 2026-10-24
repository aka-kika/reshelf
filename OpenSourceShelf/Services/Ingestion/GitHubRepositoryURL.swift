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
    /// `?query` or `#anchor` after the repo, and a trailing `.git`. Also reads
    /// `https://git@github.com:owner/repo`, which older builds stored for a
    /// pasted SSH link, so those rows work until the launch repair fixes them.
    static func ownerAndRepo(from rawValue: String) -> (owner: String, repo: String)? {
        var cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "ssh://"] where cleaned.lowercased().hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count))
            break
        }
        if cleaned.lowercased().hasPrefix("git@github.com:") {
            cleaned = "github.com/" + cleaned.dropFirst("git@github.com:".count)
        } else if cleaned.lowercased().hasPrefix("git@") {
            cleaned = String(cleaned.dropFirst("git@".count))
        }
        if cleaned.lowercased().hasPrefix("www.") {
            cleaned = String(cleaned.dropFirst(4))
        }
        guard cleaned.lowercased().hasPrefix("github.com/") else { return nil }

        // The first two pieces are the owner and the repo, even when one of
        // them is named tree or blob. Those words are only a branch path
        // after the repo (`/owner/repo/tree/main`), and the first two pieces
        // already ignore that.
        let parts = cleaned.dropFirst("github.com/".count)
            .split(separator: "/")
            .filter { !$0.isEmpty }
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

    /// `https://github.com/<owner>/<repo>` for a GitHub link written the SSH
    /// way (`git@github.com:o/r.git`, `ssh://git@github.com/o/r`, or the broken
    /// `https://git@github.com:o/r` older builds stored). Nil for every other
    /// link, so plain https links are never rewritten.
    static func webLink(fromSSH rawValue: String) -> String? {
        let lower = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("ssh://") || lower.contains("git@github.com"),
              let (owner, repo) = ownerAndRepo(from: rawValue) else { return nil }
        return "https://github.com/\(owner)/\(repo)"
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

/// GitHub's primary limit is HTTP 429 or `X-RateLimit-Remaining: 0`.
/// The secondary limit is a 403 with `Retry-After` (remaining is not 0).
/// A 403 without that header is a permissions failure, not a limit.
enum GitHubHTTP {
    static func isRateLimited(status: Int, remaining: String?, retryAfter: String?) -> Bool {
        if status == 429 || remaining == "0" { return true }
        if status == 403, let retryAfter, !retryAfter.trimmingCharacters(in: .whitespaces).isEmpty {
            return true
        }
        return false
    }
}

/// Web links as typed or pasted ("github.com/owner/repo") have no scheme, and
/// `NSWorkspace.open` then treats them as file paths (Finder error -50).
/// Lives here, next to the link reader, so a GitHub SSH link becomes the
/// https link every other part of the app can read.
enum WebLink {
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // "git@github.com:o/r" would otherwise get "https://" glued on and
        // become a link nothing can read (no clone, no icon, no duplicate check).
        if let web = GitHubRepositoryURL.webLink(fromSSH: trimmed) { return web }
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return trimmed }
        // Only a host-looking start ("github.com/…", "example.org") gets a scheme.
        let host = trimmed.split(separator: "/", maxSplits: 1).first ?? ""
        guard host.contains("."), !host.contains(" ") else { return trimmed }
        return "https://" + trimmed
    }

    /// A link the app may open. Only http and https: a repo homepage can be
    /// `file://` or `smb://`, and `NSWorkspace.open` would hand that to Finder.
    static func url(_ raw: String) -> URL? {
        let link = normalized(raw)
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
