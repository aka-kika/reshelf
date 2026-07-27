import Foundation
import SwiftData

/// Fills in `ToolProject.lastUpdatedDate` for rows captured before the field
/// existed.
///
/// Cloned repos are read straight off disk (`git log -1 --format=%cI`) — free,
/// instant, offline, and no API budget. That covers most of a working shelf.
/// Everything else needs a GitHub round trip, which is rate-limited to 60/hour
/// unauthenticated, so it is deliberately *not* swept here: those rows fill in
/// the next time their metadata is refreshed.
enum LastUpdatedBackfillService {

    struct Result {
        var filled = 0
        var skippedNotCloned = 0
        var failed = 0
    }

    /// Projects that have no date yet. The caller decides whether that's worth
    /// showing a button for.
    @MainActor
    static func projectsMissingDate(in context: ModelContext) -> [ToolProject] {
        let all = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        return all.filter { $0.lastUpdatedDate == nil }
    }

    /// Fills from local clones only. Never overwrites a date that's already set —
    /// a value from GitHub is more authoritative than a local checkout that may
    /// be behind.
    @MainActor
    @discardableResult
    static func backfillFromClones(in context: ModelContext) async -> Result {
        var result = Result()
        for project in projectsMissingDate(in: context) {
            guard let clone = CatalogCloneService.existingClone(for: project) else {
                result.skippedNotCloned += 1
                continue
            }
            if let date = await lastCommitDate(at: clone) {
                project.lastUpdatedDate = date
                result.filled += 1
            } else {
                result.failed += 1
            }
        }
        if result.filled > 0 { try? context.save() }
        return result
    }

    /// `git log -1 --format=%cI` in a checkout — committer date, ISO-8601.
    static func lastCommitDate(at repositoryURL: URL) async -> Date? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["-C", repositoryURL.path, "log", "-1", "--format=%cI"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                // Read before waiting: a full pipe would otherwise deadlock the
                // child. The output here is one short line, but the habit is
                // what stopped clone batches wedging in 1.3.2.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: GitHubDate.parse(text))
            }
        }
    }
}
