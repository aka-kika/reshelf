import Foundation
import AppKit
import SwiftData

struct GitHubRepoInfo: Codable {
    let fullName: String?
    let description: String?
    let homepage: String?
    let stars: Int?
    let license: LicenseInfo?
    let topics: [String]?
    let language: String?
    let htmlUrl: String?
    let forks: Int?
    let openIssues: Int?
    let defaultBranch: String?
    let pushedAt: String?
    let archived: Bool?
    let fork: Bool?

    struct LicenseInfo: Codable {
        let spdxId: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case spdxId = "spdx_id"
            case name
        }
    }

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description, homepage
        case stars = "stargazers_count"
        case license, topics, language
        case htmlUrl = "html_url"
        case forks = "forks_count"
        case openIssues = "open_issues_count"
        case defaultBranch = "default_branch"
        case pushedAt = "pushed_at"
        case archived, fork
    }
}

enum QuickCaptureService {
    // Parse GitHub URL and fetch repo metadata
    static func fetchRepoInfo(githubURL: String) async throws -> GitHubRepoInfo {
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: githubURL) else {
            throw CaptureError.invalidURL
        }

        let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!
        let data = try await getJSON(from: apiURL, context: "\(owner)/\(repo)")
        do {
            return try JSONDecoder().decode(GitHubRepoInfo.self, from: data)
        } catch {
            throw CaptureError.decodingFailed
        }
    }

    /// Performs the request and maps GitHub's HTTP responses to clear `CaptureError`s.
    /// `context` (e.g. "owner/repo") is woven into user-facing messages.
    private static func getJSON(from url: URL, context: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        GitHubAuth.authorize(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CaptureError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CaptureError.network("No response from GitHub.")
        }

        switch http.statusCode {
        case 200:
            return data
        case 404:
            // GitHub returns 404 both for missing repos and private repos the
            // current request can't see.
            throw CaptureError.notFound(context)
        case 401:
            throw CaptureError.unauthorized
        case 403, 429:
            // Rate limiting: distinguish from a generic 403 via the remaining header.
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if http.statusCode == 429 || remaining == "0" {
                throw CaptureError.rateLimited(resetText: rateLimitResetText(from: http))
            }
            throw CaptureError.forbidden(context)
        default:
            throw CaptureError.httpError(http.statusCode)
        }
    }

    /// Turns the `X-RateLimit-Reset` epoch header into a friendly "in N minutes" string.
    private static func rateLimitResetText(from http: HTTPURLResponse) -> String? {
        guard let resetValue = http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let epoch = TimeInterval(resetValue) else { return nil }
        let resetDate = Date(timeIntervalSince1970: epoch)
        let seconds = resetDate.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let minutes = Int(ceil(seconds / 60))
        return minutes <= 1 ? "in about a minute" : "in about \(minutes) minutes"
    }
}

/// Post-save Capture Assist: fills use cases, note, and tags on a saved project
/// with on-device Apple Intelligence. Strictly fill-only — entries that already
/// have use cases are skipped, and individual fields the user filled are never
/// overwritten.
@MainActor
enum CaptureAssistService {
    static func projectsMissingUseCases(in context: ModelContext) -> [ToolProject] {
        let all = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        return all.filter { $0.useCases.isEmpty }
    }

    /// Generates for one project and writes only its empty fields.
    /// Returns true when anything was written.
    @discardableResult
    static func fillIfNeeded(_ project: ToolProject, context: ModelContext) async -> Bool {
        guard AppleIntelligenceService.availability.isAvailable else { return false }
        guard project.useCases.isEmpty else { return false }

        let prompt = """
        Project: \(project.name)
        Description: \(project.shortDescription)
        Long description: \(project.longDescription)
        Category: \(project.category)
        GitHub stars: \(project.stars)
        License: \(project.license)
        Existing tags: \(project.tags.joined(separator: ", "))
        """
        guard let suggestion = try? await AppleIntelligenceService.suggestCapture(prompt: prompt) else {
            return false
        }

        // Re-check each field at write time — the user may have edited the entry
        // while the model was generating.
        var wrote = false
        if project.useCases.isEmpty {
            let useCases = suggestion.useCases
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !useCases.isEmpty {
                project.useCases = useCases
                wrote = true
            }
        }
        if project.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let note = suggestion.note.trimmingCharacters(in: .whitespaces)
            if !note.isEmpty {
                project.notes = note
                wrote = true
            }
        }
        if project.tags.isEmpty {
            let tags = suggestion.tags
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !tags.isEmpty {
                project.tags = tags
                wrote = true
            }
        }
        if wrote { try? context.save() }
        return wrote
    }
}

enum CaptureError: LocalizedError {
    case invalidURL
    case notFound(String)
    case unauthorized
    case forbidden(String)
    case rateLimited(resetText: String?)
    case httpError(Int)
    case decodingFailed
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Not a valid GitHub URL. Use a link like https://github.com/owner/repo."
        case let .notFound(repo):
            "Couldn't find “\(repo)”. Check the URL — or it may be a private repo this app can't access."
        case .unauthorized:
            if GitHubAuth.hasToken {
                "GitHub rejected the saved token — it may be expired or revoked. Update it in Settings → Capture."
            } else {
                "GitHub rejected the request (unauthorized). Check the repository URL."
            }
        case let .forbidden(repo):
            "GitHub blocked access to “\(repo)”. It may be private or restricted."
        case let .rateLimited(resetText):
            {
                var message = if let resetText {
                    "GitHub rate limit reached. Try again \(resetText)."
                } else {
                    "GitHub rate limit reached. Please wait a few minutes and try again."
                }
                if !GitHubAuth.hasToken {
                    message += " Adding a GitHub token in Settings → Capture raises the limit from 60 to 5,000 requests per hour."
                }
                return message
            }()
        case let .httpError(code):
            "GitHub returned an unexpected error (HTTP \(code)). Please try again."
        case .decodingFailed:
            "GitHub returned data this app couldn't read. Please try again."
        case let .network(detail):
            "Couldn't reach GitHub: \(detail)"
        }
    }
}

/// Saves a repo handed over by another app through `reshelf://add?url=<github url>`
/// (Undrdr Drop's "Send to reshelf" button). Same steps as Quick Capture's Save,
/// without the sheet: dedupe, fetch from GitHub, classify, land in The Collector.
@MainActor
enum LinkCaptureService {
    enum Outcome {
        case added(ToolProject)
        case duplicate(ToolProject)
        case failed(String)
    }

    /// The GitHub URL inside `reshelf://add?url=…`, or nil for any other link.
    static func githubURL(from link: URL) -> String? {
        guard link.scheme?.lowercased() == "reshelf",
              link.host?.lowercased() == "add",
              let raw = URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              !IconFetcher.repoDedupKey(for: raw).isEmpty else { return nil }
        return raw
    }

    static func capture(_ url: String, context: ModelContext) async -> Outcome {
        let key = IconFetcher.repoDedupKey(for: url)
        let existing = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        if let dup = existing.first(where: { IconFetcher.repoDedupKey(for: $0.githubURL) == key }) {
            return .duplicate(dup)
        }

        let info: GitHubRepoInfo
        do {
            info = try await QuickCaptureService.fetchRepoInfo(githubURL: url)
        } catch {
            return .failed(error.localizedDescription)
        }

        let name = info.fullName?.components(separatedBy: "/").last ?? url
        let topics = info.topics ?? []
        let project = ToolProject(
            name: name,
            shortDescription: info.description ?? "",
            longDescription: info.description ?? "",
            githubURL: WebLink.normalized(url),
            websiteURL: WebLink.normalized(info.homepage ?? ""),
            category: CategoryClassifier.classify(
                language: info.language,
                topics: info.topics,
                description: info.description,
                name: name
            ),
            status: .collector,
            license: info.license?.spdxId ?? info.license?.name ?? "",
            stars: info.stars.map { $0 >= 1000 ? String(format: "%.1fk", Double($0) / 1000.0) : "\($0)" } ?? "",
            tags: topics,
            lastUpdatedDate: info.pushedAt.flatMap(GitHubDate.parse),
            isLocalFirst: topics.contains("local-first"),
            isSelfHosted: topics.contains("self-hosted")
        )
        context.insert(project)
        try? context.save()
        CatalogCaptureIntelligenceService.upsertFromCatalogSave(project)
        IconFetcher.fetch(for: project, in: context)

        // Same hands-free assist Quick Capture runs after Save.
        let defaults = UserDefaults.standard
        let assistOn = defaults.object(forKey: CaptureAssist.storageKey) as? Bool ?? true
        let autoGenerate = defaults.object(forKey: CaptureAssist.autoGenerateKey) as? Bool ?? true
        if assistOn, autoGenerate {
            Task { await CaptureAssistService.fillIfNeeded(project, context: context) }
        }
        return .added(project)
    }
}
