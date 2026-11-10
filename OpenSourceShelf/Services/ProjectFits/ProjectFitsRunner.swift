import Foundation
import SwiftData

/// Runs Find Fits for one of Kika's repos, only when she asks (adding a repo,
/// New Fits). Nothing here starts on its own.
///
/// 1. Her repo: today's README and description from GitHub.
/// 2. First pass over every Top Shelf and Collector repo, from what reshelf
///    stores (plus the README of a local clone).
/// 3. The best few (the fits limit plus 10) get today's README from GitHub
///    and are scored again.
/// 4. Only real fits stay, best first, at most the limit in Settings > Fits.
/// 5. Apple Intelligence writes one why line per fit (shared words without it).
/// 6. The list is saved with the run time and scores; hidden fits stay hidden.
@MainActor
final class ProjectFitsRunner: ObservableObject {
    static let shared = ProjectFitsRunner()

    struct Progress: Equatable {
        var step: String
        var done: Int
        var total: Int
    }

    /// Runs in progress, by `MyRepo.id`.
    @Published private(set) var progress: [UUID: Progress] = [:]
    /// The last run's failure per repo, shown in the list until the next run.
    @Published private(set) var failure: [UUID: String] = [:]

    private var tasks: [UUID: Task<Void, Never>] = [:]

    /// GitHub topics, language, licence, last push and archived flag per
    /// shelf repo (`dedupKey`), from reshelf's metadata store. Set at launch.
    static var factsSource: @MainActor () -> [String: RepoFacts] = { [:] }
    private static var factsCache: [String: RepoFacts]?

    /// The facts, read once and again at every run (the list's filters use
    /// them on every redraw).
    static func facts(reload: Bool = false) -> [String: RepoFacts] {
        if reload || factsCache == nil { factsCache = factsSource() }
        return factsCache ?? [:]
    }

    /// The most fits a run keeps (Settings > Fits).
    static var limit: Int {
        let stored = UserDefaults.standard.integer(forKey: FitScorer.limitKey)
        return FitScorer.limitChoices.contains(stored) ? stored : FitScorer.defaultLimit
    }

    func isRunning(_ repoID: UUID) -> Bool { progress[repoID] != nil }

    /// Dismiss on the failure banner.
    func clearFailure(_ repoID: UUID) { failure[repoID] = nil }

    func stop(_ repoID: UUID) {
        tasks[repoID]?.cancel()
        // Stop after adding several repos stops the ones still waiting too
        // (7daa: only the one running stopped, the rest went on).
        if queued.contains(repoID) {
            queueTask?.cancel()
            queued = []
        }
    }

    /// The repos an Add run has not reached yet, and that run.
    private var queued: Set<UUID> = []
    private var queueTask: Task<Void, Never>?

    /// New Fits looks only at shelf repos new or changed since the
    /// last run; Analyze All Fits (and a first run) looks at the whole shelf.
    enum Mode: Sendable { case newOnly, all }

    /// Runs Find Fits for each repo in turn (the Add popup adds several).
    func run(_ repoIDs: [UUID], mode: Mode = .all, in context: ModelContext) {
        guard repoIDs.count > 1 else {
            if let id = repoIDs.first { Task { @MainActor in await self.run(id, mode: mode, in: context) } }
            return
        }
        // One Add run at a time; a second one waits for the first.
        let previous = queueTask
        queued.formUnion(repoIDs)
        let task = Task { @MainActor [self] in
            await previous?.value
            for id in repoIDs {
                guard !Task.isCancelled, queued.contains(id) else { break }
                await run(id, mode: mode, in: context)
                queued.remove(id)
            }
        }
        queueTask = task
    }

    /// Waits for the Add run in progress (tests).
    func waitForQueue() async { await queueTask?.value }

    /// READMEs read during one run over all her repos: each shelf README is
    /// fetched once for the batch, not once per repo of hers (d135: about
    /// 280 calls for 11 repos). A failed read is not kept.
    final class ReadmeCache: @unchecked Sendable {
        private let lock = NSLock()
        private var pages: [String: String?] = [:]

        func readme(fullName: String) async throws -> String? {
            let key = fullName.lowercased()
            lock.lock()
            let known = pages[key]
            lock.unlock()
            if let known { return known }
            let page = try await ProjectFitsGitHub.readme(fullName: fullName)
            lock.lock()
            pages[key] = .some(page)
            lock.unlock()
            return page
        }
    }

    /// One run over all her repos (right-click the My Repos heading): one
    /// after another, each with its own filter, one progress line.
    struct Batch: Equatable {
        var done: Int
        var total: Int
        var current: String
    }
    @Published private(set) var batch: Batch?
    private var batchTask: Task<Void, Never>?
    private var batchCurrent: UUID?

    func runAll(_ repoIDs: [UUID], mode: Mode, in context: ModelContext) async {
        guard batch == nil, !repoIDs.isEmpty else { return }
        batch = Batch(done: 0, total: repoIDs.count, current: "")
        let readmes = ReadmeCache()
        let task = Task { @MainActor [self] in
            for (index, id) in repoIDs.enumerated() {
                if Task.isCancelled { break }
                batchCurrent = id
                batch = Batch(done: index, total: repoIDs.count,
                              current: ProjectFitsService.repo(id, in: context)?.displayName ?? "")
                await run(id, mode: mode, in: context, readmes: readmes)
            }
        }
        batchTask = task
        await task.value
        batchTask = nil
        batchCurrent = nil
        batch = nil
    }

    /// Stop for the whole run: the repo in progress stops too and keeps its
    /// saved list; the ones not reached yet are left as they were.
    func stopAll() {
        batchTask?.cancel()
        if let id = batchCurrent { stop(id) }
    }

    func run(_ repoID: UUID, mode: Mode = .all, in context: ModelContext, readmes: ReadmeCache? = nil) async {
        guard tasks[repoID] == nil, let repo = ProjectFitsService.repo(repoID, in: context) else { return }
        let fullName = repo.fullName
        let summary = repo.summary
        let projectKey = fullName.lowercased()
        let hidden = Set(ProjectFitsService.fits(for: repoID, in: context).filter(\.isHidden).map(\.repoKey))
        let inputs = Self.candidateInputs(in: context, excluding: projectKey, facts: Self.facts(reload: true))
        let others = ProjectFitsService.repos(in: context)
            .filter { $0.id != repoID && $0.fullName.lowercased() != projectKey }
            .map { OtherRepo(id: $0.id, fullName: $0.fullName,
                             text: $0.matchText.isEmpty ? $0.summary : $0.matchText,
                             needsReadme: $0.matchText.isEmpty) }
        // Its own filter (right-click > Filter), or Settings > Fits.
        let settings = FitSettings.resolved(ownJSON: repo.fitSettingsJSON, main: .main())
        let limit = settings.limit
        let filters = settings.filters
        let projectLanguage = repo.language
        let signature = FitScorer.runSignature(limit: limit, filters: filters.signature)
        // Only new repos when the saved list was made the same way (same
        // scoring, limit and filters); otherwise the whole shelf.
        let top = Set(inputs.filter(\.isTopShelf).map(\.key))
        // The list as she sees it (not hidden, not pushed off last time).
        let saved = ProjectFitsService.fits(for: repoID, in: context).filter { !$0.isHidden && !$0.isBumped }.map {
            FitIncremental.Saved(key: $0.repoKey, why: $0.why, score: $0.score,
                                 isTopShelf: top.contains($0.repoKey), isPinned: $0.isPinned)
        }
        var incremental: Incremental?
        if mode == .newOnly, let last = repo.lastRunAt, repo.runSignature == signature, !repo.matchText.isEmpty {
            incremental = Incremental(
                projectText: repo.matchText,
                changed: FitIncremental.changed(inputs.map { ($0.key, $0.added, $0.updated) }, since: last),
                saved: saved)
        }
        failure[repoID] = nil
        progress[repoID] = Progress(step: "Reading \(repo.displayName)", done: 0, total: 0)

        let task = Task { @MainActor [self] in
            do {
                let outcome = try await Self.findFits(fullName: fullName, summary: summary, inputs: inputs,
                                                      hidden: hidden, others: others,
                                                      limit: limit, filters: filters,
                                                      projectLanguage: projectLanguage,
                                                      incremental: incremental, saved: saved,
                                                      readmes: readmes) { [weak self] step in
                    self?.progress[repoID] = step
                }
                guard !Task.isCancelled else { return }
                ProjectFitsService.saveMatchTexts(outcome.otherTexts, in: context)
                ProjectFitsService.applyRun(repoID: repoID, found: outcome.fits.map { ($0.key, $0.why) },
                                            scores: outcome.scores, madeRoom: outcome.madeRoom,
                                            pinned: outcome.pinned, matchText: outcome.projectText,
                                            signature: signature, language: outcome.language,
                                            note: outcome.note, in: context)
            } catch is CancellationError {
                // Stopped: the saved list stays as it was.
            } catch {
                self.failure[repoID] = error.localizedDescription
            }
        }
        tasks[repoID] = task
        await task.value
        tasks[repoID] = nil
        progress[repoID] = nil
    }

    // MARK: - Inputs (main thread: models stay here)

    struct CandidateInput: Sendable {
        let key: String
        let name: String
        let isTopShelf: Bool
        let fullName: String
        let storedText: String
        let summary: String
        let clonePath: URL?
        var facts: RepoFacts? = nil
        var license: String = ""
        /// When it came onto the shelf, and when it last changed upstream as
        /// far as reshelf knows (New Fits looks at what is newer).
        var added: Date = .distantPast
        var updated: Date? = nil
    }

    /// New Fits: her saved text and list, and which shelf repos are
    /// new or changed since the last run.
    struct Incremental: Sendable {
        let projectText: String
        let changed: Set<String>
        let saved: [FitIncremental.Saved]
    }

    /// One of her other repos, for what all her repos share.
    struct OtherRepo: Sendable {
        let id: UUID
        let fullName: String
        let text: String
        /// No README read for it yet: this run reads it once and saves it.
        let needsReadme: Bool
    }

    /// Top Shelf and The Collector, never Yard Sale (it is on the way out),
    /// never her own repo.
    static func candidateInputs(in context: ModelContext, excluding projectKey: String,
                                facts: [String: RepoFacts] = [:]) -> [CandidateInput] {
        let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        var seen = Set<String>()
        var out: [CandidateInput] = []
        for project in projects where project.status != .yardSale {
            guard let parsed = GitHubRepositoryURL.parse(project.githubURL) else { continue }
            let key = GitHubRepositoryURL.dedupKey(for: project.githubURL)
            guard key != projectKey, seen.insert(key).inserted else { continue }
            let known = facts[key]
            let text = [project.name, project.shortDescription, project.longDescription, project.category,
                        project.tags.joined(separator: " "), project.useCases.joined(separator: " "),
                        project.notes, project.personalNote,
                        (known?.topics ?? []).joined(separator: " ")].joined(separator: "\n")
            out.append(CandidateInput(
                key: key, name: project.name, isTopShelf: project.status == .topShelf,
                fullName: parsed.fullName, storedText: text,
                summary: project.shortDescription.isEmpty ? project.longDescription : project.shortDescription,
                clonePath: CatalogCloneService.isCloned(project) ? CatalogCloneService.existingClone(for: project) : nil,
                facts: known, license: project.license, added: project.addedDate,
                updated: project.lastUpdatedDate))
        }
        return out
    }

    // MARK: - The run (off the main thread where it can be)

    struct Outcome {
        let fits: [(key: String, why: String)]
        let note: String
        /// Fit score per key, saved with the list.
        var scores: [String: Double] = [:]
        /// Her repo's text this run matched, saved for other runs.
        var projectText: String = ""
        /// Other repos of hers whose README this run read for the first time.
        var otherTexts: [UUID: String] = [:]
        /// Her repo's language when this run read it ("" otherwise).
        var language: String = ""
        /// Saved fits the limit pushed off this run, and the kept (pinned) keys.
        var madeRoom: [FitIncremental.Saved] = []
        var pinned: Set<String> = []
    }

    enum RunError: LocalizedError {
        case nothingToMatch(String)
        case emptyShelf

        var errorDescription: String? {
            switch self {
            case .nothingToMatch(let name):
                return "\(name) has no README or description to match against. Add a README on GitHub, then try again."
            case .emptyShelf:
                return "There are no Top Shelf or Collector repos to match yet."
            }
        }
    }

    nonisolated static func findFits(fullName: String, summary: String, inputs: [CandidateInput],
                                     hidden: Set<String>, others: [OtherRepo] = [],
                                     limit: Int = FitScorer.defaultLimit, filters: FitFilters = FitFilters(),
                                     projectLanguage: String = "", incremental: Incremental? = nil,
                                     saved: [FitIncremental.Saved] = [],
                                     readmes: ReadmeCache? = nil,
                                     report: @escaping @MainActor (Progress) -> Void) async throws -> Outcome {
        // A shelf or other-repo README: once per batch when a cache is given.
        func readme(_ fullName: String) async throws -> String? {
            if let readmes { return try await readmes.readme(fullName: fullName) }
            return try await ProjectFitsGitHub.readme(fullName: fullName)
        }
        guard !inputs.isEmpty else { throw RunError.emptyShelf }
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName

        // Her repo's language, once (Settings > Fits > Same language).
        var language = projectLanguage
        var readLanguage = ""
        if language.isEmpty, incremental == nil || filters.sameLanguage {
            readLanguage = (try? await ProjectFitsGitHub.language(fullName: fullName)) ?? ""
            language = readLanguage
        }
        // Settings > Fits: only repos that pass take part (and stay listed).
        let onShelf = Set(inputs.filter {
            filters.allows(projectLanguage: language, facts: $0.facts, license: $0.license, lastUpdated: $0.updated)
        }.map(\.key))

        // 1. Her repo, live (New Fits keeps the text the saved list
        //    was matched against, so old and new scores compare).
        let projectText: String
        if let incremental {
            projectText = incremental.projectText
        } else {
            let readme = try await ProjectFitsGitHub.readme(fullName: fullName) ?? ""
            projectText = [summary, FitScorer.cleanReadme(readme)].joined(separator: "\n")
        }
        guard !FitScorer.tokens(projectText).isEmpty else { throw RunError.nothingToMatch(name) }
        try Task.checkCancellation()

        // Nothing new on the shelf: the saved list stands, no calls at all.
        let pinned = Set((incremental?.saved ?? saved).filter(\.isPinned).map(\.key))
        if let incremental, incremental.changed.isEmpty {
            let limited = FitIncremental.mergeLimited(saved: incremental.saved, new: [], changed: [],
                                                      onShelf: onShelf, limit: limit)
            return Outcome(fits: limited.list.map { ($0.key, $0.why) },
                           note: "Nothing new on your shelf since the last run.",
                           scores: Dictionary(limited.list.map { ($0.key, $0.score) }, uniquingKeysWith: { a, _ in a }),
                           projectText: projectText, language: readLanguage, madeRoom: limited.madeRoom,
                           pinned: pinned)
        }

        // Her other repos: what they all share counts less. A README not read
        // before is read once here (a few calls the first time only).
        var otherTexts: [UUID: String] = [:]
        var ownTexts: [String] = []
        let unread = others.filter(\.needsReadme)
        for other in others {
            try Task.checkCancellation()
            var text = other.text
            if other.needsReadme {
                await report(Progress(step: "Reading your other repos", done: otherTexts.count, total: unread.count))
                // No README (nil) is saved too, so it is not asked again; a
                // failed call (limit, network) is tried again next run.
                do {
                    if let live = try await readme(other.fullName) {
                        text = [other.text, FitScorer.cleanReadme(live)].joined(separator: "\n")
                    }
                    otherTexts[other.id] = text
                } catch {}
            }
            ownTexts.append(text)
        }

        // 2. First pass: stored text, plus a clone's README from disk.
        await report(Progress(step: "Comparing with your shelf", done: 0, total: 0))
        var candidates = inputs.map { input -> FitScorer.Candidate in
            var text = input.storedText
            if let path = input.clonePath, let local = ProjectFitsGitHub.readmeOnDisk(at: path) {
                text += "\n" + FitScorer.cleanReadme(local)
            }
            return FitScorer.Candidate(key: input.key, name: input.name, isTopShelf: input.isTopShelf, text: text)
        }
        let first = FitScorer.ordered(FitScorer.score(project: projectText, others: ownTexts, candidates: candidates))
            .filter {
                onShelf.contains($0.candidate.key) && !hidden.contains($0.candidate.key)
                    && (incremental?.changed.contains($0.candidate.key) ?? true)
            }
        try Task.checkCancellation()

        // 3. Today's README for the best few.
        let shortlist = Array(first.prefix(FitScorer.shortlistCount(for: limit))).map(\.candidate.key)
        let byKey = Dictionary(uniqueKeysWithValues: inputs.map { ($0.key, $0) })
        var limitHit = false
        var usedSaved = 0
        for (index, key) in shortlist.enumerated() {
            try Task.checkCancellation()
            await report(Progress(step: "Reading READMEs", done: index, total: shortlist.count))
            guard let input = byKey[key], let i = candidates.firstIndex(where: { $0.key == key }) else { continue }
            if limitHit { usedSaved += 1; continue }
            do {
                if let live = try await readme(input.fullName) {
                    candidates[i].text = input.storedText + "\n" + FitScorer.cleanReadme(live)
                }
            } catch CaptureError.rateLimited {
                limitHit = true
                usedSaved += 1
            } catch {
                usedSaved += 1
            }
        }

        // Second pass over the whole shelf (so word weights stay the same),
        // keeping only the ones that were read again.
        let shortSet = Set(shortlist)
        let second = FitScorer.score(project: projectText, others: ownTexts, candidates: candidates)
            .filter { shortSet.contains($0.candidate.key) }
        // Every real fit first; the limit (and kept ones) decide below.
        let picked = FitScorer.pick(second, hidden: hidden, limit: .max)
        try Task.checkCancellation()

        // New Fits: the new fits join the saved list by score. Analyze All
        // Fits: the fresh list, plus fits she kept. Either way, saved fits
        // the limit pushes off "made room".
        let pickedSaved = picked.map {
            FitIncremental.Saved(key: $0.candidate.key, why: "", score: $0.score, isTopShelf: $0.candidate.isTopShelf)
        }
        let limited: FitIncremental.Limited
        if let incremental {
            limited = FitIncremental.mergeLimited(saved: incremental.saved, new: pickedSaved,
                                                  changed: incremental.changed, onShelf: onShelf, limit: limit,
                                                  rescored: shortSet)
        } else {
            let pickedKeys = Set(pickedSaved.map(\.key))
            let keptStill = saved.filter { $0.isPinned && onShelf.contains($0.key) && !pickedKeys.contains($0.key) }
            let savedWhy = Dictionary(saved.map { ($0.key, $0.why) }, uniquingKeysWith: { a, _ in a })
            let fresh = pickedSaved.map { item -> FitIncremental.Saved in
                FitIncremental.Saved(key: item.key, why: savedWhy[item.key] ?? "", score: item.score,
                                     isTopShelf: item.isTopShelf, isPinned: pinned.contains(item.key))
            }
            limited = FitIncremental.applyLimit(fresh + keptStill, pinned: pinned,
                                                previous: Set(saved.map(\.key)), limit: limit)
        }
        let final = limited.list
        let pickedByKey = Dictionary(picked.map { ($0.candidate.key, $0) }, uniquingKeysWith: { a, _ in a })
        // A why line is written for fits new on the list; saved ones keep
        // theirs, on New Fits and on Analyze All Fits alike (b493: a full run
        // rewrote every line, up to 25 slow generations, and turned written
        // sentences into "Shares: …" with Apple Intelligence off).
        let toWrite = final.filter { $0.why.isEmpty }.compactMap { pickedByKey[$0.key] }

        // 4. Why lines, for the fits this run found.
        var whyByKey: [String: String] = [:]
        let canWrite = AppleIntelligenceService.availability.isAvailable
        for (index, fit) in toWrite.enumerated() {
            try Task.checkCancellation()
            await report(Progress(step: "Writing why lines", done: index, total: toWrite.count))
            var why = FitScorer.fallbackWhy(fit)
            if canWrite, let input = byKey[fit.candidate.key] {
                let prompt = """
                    Her project: \(name). \(String(projectText.prefix(1500)))

                    Shelf repo: \(input.name). \(input.summary) \
                    \(String(fit.candidate.text.prefix(1500)))

                    Words both share: \(fit.sharedTerms.joined(separator: ", ")).
                    In one sentence, what in the shelf repo helps her project?
                    """
                if let line = try? await AppleIntelligenceService.whyItFits(prompt: prompt), !line.isEmpty {
                    why = line
                }
            }
            whyByKey[fit.candidate.key] = why
        }
        let fits = final.map { ($0.key, whyByKey[$0.key] ?? $0.why) }

        var note = ""
        if let incremental {
            let n = incremental.changed.count
            note = "Looked at \(n) repo\(n == 1 ? "" : "s") new or changed since the last run."
        }
        if limitHit {
            note = "GitHub's limit was reached: \(usedSaved) repo\(usedSaved == 1 ? "" : "s") used saved info. A token in Settings raises the limit."
        } else if usedSaved > 0 {
            note = "\(usedSaved) README\(usedSaved == 1 ? "" : "s") could not be read; saved info was used."
        }
        return Outcome(fits: fits, note: note,
                       scores: Dictionary(final.map { ($0.key, $0.score) }, uniquingKeysWith: { a, _ in a }),
                       projectText: projectText, otherTexts: otherTexts, language: readLanguage,
                       madeRoom: limited.madeRoom, pinned: pinned)
    }
}
