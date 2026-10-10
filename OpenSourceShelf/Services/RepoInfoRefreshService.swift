import Foundation
import SwiftData

/// Re-reads GitHub facts for repos already on the shelf (Shelf → Refresh Repo
/// Info, and after a clone is pulled).
///
/// Only what GitHub owns is overwritten: star count, license, last activity
/// date. The description and website are filled only when empty, because the
/// user may have edited them. Tags, notes, category and shelf are never touched.
@MainActor
enum RepoInfoRefreshService {
    struct Result {
        var checked = 0
        var starsChanged = 0
        var licensesChanged = 0
        /// Repos GitHub answered 404 for (deleted, renamed away, or private).
        var notFound: [ToolProject] = []
        var failed = 0
        /// Set when GitHub's rate limit stopped the run early.
        var rateLimitMessage: String?
    }

    /// GitHub requests in flight at once: quick, and well inside the limits.
    private static let parallelRequests = 6

    /// Repos on `shelf` that have a GitHub link and no local clone. Cloned
    /// repos refresh when they are pulled.
    static func candidates(on shelf: ProjectStatus, in projects: [ToolProject]) -> [ToolProject] {
        projects.filter {
            $0.status == shelf
                && !$0.githubURL.trimmingCharacters(in: .whitespaces).isEmpty
                && !CatalogCloneService.isCloned($0)
        }
    }

    /// One finished GitHub request, tagged with the position of its project.
    private struct Fetched: Sendable {
        let position: Int
        let outcome: Swift.Result<GitHubRepoInfo, Error>
    }

    /// Fetches and applies fresh info for `projects`, saving once at the end.
    /// `progress` gets (done, total) after each repo.
    static func refresh(_ projects: [ToolProject],
                        context: ModelContext,
                        progress: @escaping (Int, Int) -> Void = { _, _ in }) async -> Result {
        var result = Result()
        // Plain values cross into the network tasks; the models stay on main.
        let urls = projects.map(\.githubURL)
        var nextPosition = 0
        var done = 0

        await withTaskGroup(of: Fetched.self) { group in
            // Keep `parallelRequests` in flight: start that many, then one more
            // each time one finishes.
            while nextPosition < min(parallelRequests, urls.count) {
                let position = nextPosition
                let url = urls[position]
                group.addTask { await fetch(url, position: position) }
                nextPosition += 1
            }

            for await fetched in group {
                let project = projects[fetched.position]
                switch fetched.outcome {
                case .success(let info):
                    apply(info, to: project, result: &result)
                    result.checked += 1
                case .failure(let error):
                    switch error as? CaptureError {
                    case .notFound:
                        result.notFound.append(project)
                    case .rateLimited(let resetText):
                        result.rateLimitMessage = "GitHub's request limit was reached"
                            + (resetText.map { "; it resets \($0)" } ?? "")
                            + ". Adding a token in Settings → Capture raises it."
                    default:
                        result.failed += 1
                    }
                }
                done += 1
                progress(done, urls.count)

                if nextPosition < urls.count, result.rateLimitMessage == nil {
                    let position = nextPosition
                    let url = urls[position]
                    group.addTask { await fetch(url, position: position) }
                    nextPosition += 1
                }
            }
        }

        if result.checked > 0 { try? context.save() }
        return result
    }

    private nonisolated static func fetch(_ url: String, position: Int) async -> Fetched {
        do {
            return Fetched(position: position,
                           outcome: .success(try await QuickCaptureService.fetchRepoInfo(githubURL: url)))
        } catch {
            return Fetched(position: position, outcome: .failure(error))
        }
    }

    private static func apply(_ info: GitHubRepoInfo, to project: ToolProject, result: inout Result) {
        if let count = info.stars {
            let stars = GitHubRepoInfo.formattedStars(count)
            if stars != project.stars {
                project.stars = stars
                result.starsChanged += 1
            }
        }
        // GitHub omits the license object when there is none; that is a real
        // answer ("no license"), so it clears a stale value too.
        let license = info.licenseText
        if license != project.license {
            project.license = license
            result.licensesChanged += 1
        }
        if let pushed = info.pushedAt.flatMap(GitHubDate.parse) {
            project.lastUpdatedDate = pushed
        }
        if project.shortDescription.trimmingCharacters(in: .whitespaces).isEmpty,
           let description = info.description, !description.isEmpty {
            project.shortDescription = description
        }
        if project.websiteURL.trimmingCharacters(in: .whitespaces).isEmpty,
           let homepage = info.homepage, !homepage.isEmpty {
            project.websiteURL = WebLink.normalized(homepage)
        }
    }
}
