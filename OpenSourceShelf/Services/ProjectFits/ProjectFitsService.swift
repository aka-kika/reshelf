import Foundation
import SwiftData

/// Every My Repos and fits change goes through here (like
/// `CatalogFolderService` for folders). Removing a repo from the sidebar
/// removes its fits and nothing else: the shelf repos are untouched.
@MainActor
enum ProjectFitsService {

    static func repos(in context: ModelContext) -> [MyRepo] {
        let all = (try? context.fetch(FetchDescriptor<MyRepo>())) ?? []
        return all.sorted {
            $0.sortIndex == $1.sortIndex
                ? $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                : $0.sortIndex < $1.sortIndex
        }
    }

    static func repo(_ id: UUID, in context: ModelContext) -> MyRepo? {
        var descriptor = FetchDescriptor<MyRepo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func fits(for repoID: UUID, in context: ModelContext) -> [RepoFit] {
        let descriptor = FetchDescriptor<RepoFit>(
            predicate: #Predicate { $0.myRepoID == repoID },
            sortBy: [SortDescriptor(\.rank)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Adds repos not in the sidebar yet (by `owner/name`, ignoring case).
    /// Returns the ones added, in the order given.
    @discardableResult
    static func add(_ items: [(fullName: String, githubURL: String, summary: String)],
                    in context: ModelContext) -> [MyRepo] {
        var existing = Set(repos(in: context).map { $0.fullName.lowercased() })
        var next = (repos(in: context).map(\.sortIndex).max() ?? -1) + 1
        var added: [MyRepo] = []
        for item in items where !existing.contains(item.fullName.lowercased()) {
            let repo = MyRepo(fullName: item.fullName, githubURL: item.githubURL,
                              summary: item.summary, sortIndex: next)
            context.insert(repo)
            added.append(repo)
            existing.insert(item.fullName.lowercased())
            next += 1
        }
        if !added.isEmpty { save(context) }
        return added
    }

    /// Removes the repo and its fits. The shelf repos stay as they are.
    static func remove(_ repo: MyRepo, in context: ModelContext) {
        for fit in fits(for: repo.id, in: context) { context.delete(fit) }
        context.delete(repo)
        save(context)
    }

    /// Saves one finished run: merges with the saved list (hidden ones stay
    /// hidden, new ones get the dot) and stamps the run time. `found` is in
    /// list order, best fit first.
    static func applyRun(repoID: UUID, found: [(key: String, why: String)], scores: [String: Double] = [:],
                         madeRoom: [FitIncremental.Saved] = [], pinned: Set<String> = [],
                         matchText: String? = nil, signature: String? = nil, language: String? = nil,
                         note: String,
                         at date: Date = Date(), in context: ModelContext) {
        guard let repo = repo(repoID, in: context) else { return }
        let saved = fits(for: repoID, in: context)
        // Fits pushed off by the run before are dropped now: "made room"
        // lasts until the next run.
        let previous = saved.filter { !$0.isBumped || $0.isHidden }.map {
            FitMerge.Row(key: $0.repoKey, rank: $0.rank, why: $0.why, isNew: $0.isNew, isHidden: $0.isHidden,
                         score: $0.score)
        }
        let merged = FitMerge.merge(previous: previous, found: found, isFirstRun: repo.lastRunAt == nil)
        for fit in saved { context.delete(fit) }
        for row in merged {
            context.insert(RepoFit(myRepoID: repoID, repoKey: row.key, rank: row.rank, why: row.why,
                                   isNew: row.isNew, isHidden: row.isHidden,
                                   score: row.isHidden ? row.score : (scores[row.key] ?? row.score),
                                   isPinned: !row.isHidden && pinned.contains(row.key)))
        }
        let listed = Set(merged.map(\.key))
        for (offset, item) in madeRoom.enumerated() where !listed.contains(item.key) {
            context.insert(RepoFit(myRepoID: repoID, repoKey: item.key, rank: merged.count + offset, why: item.why,
                                   isNew: false, isHidden: false, score: item.score, isBumped: true))
        }
        if let matchText { repo.matchText = matchText }
        if let signature { repo.runSignature = signature }
        if let language, !language.isEmpty { repo.language = language }
        repo.previousRunAt = repo.lastRunAt
        repo.lastRunAt = date
        repo.lastRunNote = note
        save(context)
    }

    /// Right-click > Filter: gives the repo its own Fits settings, or (nil)
    /// puts it back on the main ones.
    static func setOwnSettings(_ settings: FitSettings?, for repoID: UUID, in context: ModelContext) {
        guard let repo = repo(repoID, in: context) else { return }
        let json = settings?.json ?? ""
        guard repo.fitSettingsJSON != json else { return }
        repo.fitSettingsJSON = json
        save(context)
    }

    /// Her other repos whose README a run read for the first time.
    static func saveMatchTexts(_ texts: [UUID: String], in context: ModelContext) {
        guard !texts.isEmpty else { return }
        for (id, text) in texts { repo(id, in: context)?.matchText = text }
        save(context)
    }

    /// "Keep" on a fit that made room: back on the list for good (pinned),
    /// and the weakest fit not kept goes instead when the list is full.
    static func keep(_ repoKey: String, repoID: UUID, limit: Int, in context: ModelContext) {
        let all = fits(for: repoID, in: context)
        guard let fit = all.first(where: { $0.repoKey == repoKey }) else { return }
        fit.isBumped = false
        fit.isPinned = true
        fit.isHidden = false
        let listed = all.filter { !$0.isHidden && !$0.isBumped }
        if listed.count > limit,
           let weakest = listed.filter({ !$0.isPinned }).min(by: { $0.score < $1.score }) {
            weakest.isBumped = true
        }
        // Ranks follow the score again, the made-room ones after the list.
        let order = all.filter { !$0.isHidden && !$0.isBumped }.sorted { $0.score > $1.score }
            + all.filter { $0.isBumped }.sorted { $0.score > $1.score }
        for (index, item) in order.enumerated() { item.rank = index }
        save(context)
    }

    static func setHidden(_ hidden: Bool, repoKey: String, repoID: UUID, in context: ModelContext) {
        guard let fit = fits(for: repoID, in: context).first(where: { $0.repoKey == repoKey }) else { return }
        fit.isHidden = hidden
        if !hidden { fit.isNew = false }
        save(context)
    }

    // MARK: - Backups and export

    /// What backups carry, kept current after every change here so a backup
    /// written from a plain list of rows (most "Before …" backups) has it too.
    /// Read and written on the main thread only.
    private(set) static var latestSnapshot: [MyRepoDTO] = []

    static func refreshSnapshot(in context: ModelContext) {
        latestSnapshot = snapshot(in: context)
    }

    static func snapshot(in context: ModelContext) -> [MyRepoDTO] {
        let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        var byKey: [String: ToolProject] = [:]
        for project in projects where !project.githubURL.isEmpty {
            byKey[GitHubRepositoryURL.dedupKey(for: project.githubURL)] = project
        }
        return repos(in: context).map { repo in
            MyRepoDTO(
                fullName: repo.fullName, githubURL: repo.githubURL, summary: repo.summary,
                addedAt: repo.addedAt, sortIndex: repo.sortIndex,
                lastRunAt: repo.lastRunAt, previousRunAt: repo.previousRunAt,
                lastRunNote: repo.lastRunNote,
                fits: fits(for: repo.id, in: context).map { fit in
                    let row = byKey[fit.repoKey]
                    return RepoFitDTO(repo: fit.repoKey, name: row?.name ?? "",
                                      githubURL: row?.githubURL ?? "", shelf: row?.statusRaw ?? "",
                                      rank: fit.rank, why: fit.why, isNew: fit.isNew, isHidden: fit.isHidden,
                                      score: fit.score, isPinned: fit.isPinned ? true : nil,
                                      isBumped: fit.isBumped ? true : nil)
                },
                language: repo.language,
                fitSettings: repo.fitSettingsJSON.isEmpty ? nil : repo.fitSettingsJSON)
        }
    }

    /// Import and restore: adds the repos from a file that this Mac does not
    /// have yet, with their fits. A repo already in the sidebar keeps its own
    /// list: the newer run on this Mac wins over a file.
    @discardableResult
    static func merge(_ rows: [MyRepoDTO], in context: ModelContext) -> Int {
        let have = Set(repos(in: context).map { $0.fullName.lowercased() })
        var next = (repos(in: context).map(\.sortIndex).max() ?? -1) + 1
        var added = 0
        for row in rows where !have.contains(row.fullName.lowercased()) {
            let repo = MyRepo(fullName: row.fullName, githubURL: row.githubURL,
                              summary: row.summary, sortIndex: next)
            repo.addedAt = row.addedAt
            repo.lastRunAt = row.lastRunAt
            repo.previousRunAt = row.previousRunAt
            repo.lastRunNote = row.lastRunNote
            repo.language = row.language ?? ""
            repo.fitSettingsJSON = row.fitSettings.flatMap { FitSettings.decode($0)?.json } ?? ""
            context.insert(repo)
            for fit in row.fits {
                context.insert(RepoFit(myRepoID: repo.id, repoKey: fit.repo, rank: fit.rank,
                                       why: fit.why, isNew: fit.isNew, isHidden: fit.isHidden,
                                       score: fit.score ?? 0, isPinned: fit.isPinned ?? false,
                                       isBumped: fit.isBumped ?? false))
            }
            next += 1
            added += 1
        }
        if added > 0 { save(context) }
        return added
    }

    private static func save(_ context: ModelContext) {
        CatalogSave.save(context, "your repos and their fits")
        refreshSnapshot(in: context)
    }
}
