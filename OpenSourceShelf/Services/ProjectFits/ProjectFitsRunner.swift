import Foundation
import NaturalLanguage
import SwiftData

/// Runs Find Fits for one of Kika's repos, only when she asks (adding a repo,
/// Find Fits Again). Nothing here starts on its own.
///
/// 1. Her repo: today's README and description from GitHub.
/// 2. First pass over every Top Shelf and Collector repo, from what reshelf
///    stores (plus the README of a local clone).
/// 3. The best 25 get today's README from GitHub and are scored again.
/// 4. Apple Intelligence writes one why line per fit (shared words without it).
/// 5. The list is saved with the run time; hidden fits stay hidden.
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

    func isRunning(_ repoID: UUID) -> Bool { progress[repoID] != nil }

    func stop(_ repoID: UUID) {
        tasks[repoID]?.cancel()
    }

    /// Runs Find Fits for each repo in turn (the Add popup adds several).
    func run(_ repoIDs: [UUID], in context: ModelContext) {
        Task { @MainActor in
            for id in repoIDs { await self.run(id, in: context) }
        }
    }

    func run(_ repoID: UUID, in context: ModelContext) async {
        guard tasks[repoID] == nil, let repo = ProjectFitsService.repo(repoID, in: context) else { return }
        let fullName = repo.fullName
        let summary = repo.summary
        let projectKey = fullName.lowercased()
        let hidden = Set(ProjectFitsService.fits(for: repoID, in: context).filter(\.isHidden).map(\.repoKey))
        let inputs = Self.candidateInputs(in: context, excluding: projectKey)
        failure[repoID] = nil
        progress[repoID] = Progress(step: "Reading \(repo.displayName)", done: 0, total: 0)

        let task = Task { @MainActor [self] in
            do {
                let outcome = try await Self.findFits(fullName: fullName, summary: summary, inputs: inputs,
                                                      hidden: hidden) { [weak self] step in
                    self?.progress[repoID] = step
                }
                guard !Task.isCancelled else { return }
                ProjectFitsService.applyRun(repoID: repoID, found: outcome.fits, note: outcome.note, in: context)
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
    }

    /// Top Shelf and The Collector, never Yard Sale (it is on the way out),
    /// never her own repo.
    static func candidateInputs(in context: ModelContext, excluding projectKey: String) -> [CandidateInput] {
        let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        var seen = Set<String>()
        var out: [CandidateInput] = []
        for project in projects where project.status != .yardSale {
            guard let parsed = GitHubRepositoryURL.parse(project.githubURL) else { continue }
            let key = GitHubRepositoryURL.dedupKey(for: project.githubURL)
            guard key != projectKey, seen.insert(key).inserted else { continue }
            let text = [project.name, project.shortDescription, project.longDescription, project.category,
                        project.tags.joined(separator: " "), project.useCases.joined(separator: " "),
                        project.notes, project.personalNote].joined(separator: "\n")
            out.append(CandidateInput(
                key: key, name: project.name, isTopShelf: project.status == .topShelf,
                fullName: parsed.fullName, storedText: text,
                summary: project.shortDescription.isEmpty ? project.longDescription : project.shortDescription,
                clonePath: CatalogCloneService.isCloned(project) ? CatalogCloneService.existingClone(for: project) : nil))
        }
        return out
    }

    // MARK: - The run (off the main thread where it can be)

    struct Outcome {
        let fits: [(key: String, why: String)]
        let note: String
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
                                     hidden: Set<String>,
                                     report: @escaping @MainActor (Progress) -> Void) async throws -> Outcome {
        guard !inputs.isEmpty else { throw RunError.emptyShelf }
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName

        // 1. Her repo, live.
        let readme = try await ProjectFitsGitHub.readme(fullName: fullName) ?? ""
        let projectText = [summary, FitScorer.cleanReadme(readme)].joined(separator: "\n")
        guard !FitScorer.tokens(projectText).isEmpty else { throw RunError.nothingToMatch(name) }
        try Task.checkCancellation()

        // 2. First pass: stored text, plus a clone's README from disk.
        await report(Progress(step: "Comparing with your shelf", done: 0, total: 0))
        var candidates = inputs.map { input -> FitScorer.Candidate in
            var text = input.storedText
            if let path = input.clonePath, let local = ProjectFitsGitHub.readmeOnDisk(at: path) {
                text += "\n" + FitScorer.cleanReadme(local)
            }
            return FitScorer.Candidate(key: input.key, name: input.name, isTopShelf: input.isTopShelf, text: text)
        }
        let first = rank(projectText, candidates)
        try Task.checkCancellation()

        // 3. Today's README for the best 25.
        let shortlist = Array(first.prefix(FitScorer.liveReadmeCount)).map(\.candidate.key)
        let byKey = Dictionary(uniqueKeysWithValues: inputs.map { ($0.key, $0) })
        var limitHit = false
        var usedSaved = 0
        for (index, key) in shortlist.enumerated() {
            try Task.checkCancellation()
            await report(Progress(step: "Reading READMEs", done: index, total: shortlist.count))
            guard let input = byKey[key], let i = candidates.firstIndex(where: { $0.key == key }) else { continue }
            if limitHit { usedSaved += 1; continue }
            do {
                if let live = try await ProjectFitsGitHub.readme(fullName: input.fullName) {
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
        // keeping only the 25 that were read again.
        let shortSet = Set(shortlist)
        let second = rank(projectText, candidates).filter { shortSet.contains($0.candidate.key) }
        let picked = FitScorer.pick(second, hidden: hidden)
        try Task.checkCancellation()

        // 4. Why lines.
        var fits: [(key: String, why: String)] = []
        let canWrite = AppleIntelligenceService.availability.isAvailable
        for (index, fit) in picked.enumerated() {
            try Task.checkCancellation()
            await report(Progress(step: "Writing why lines", done: index, total: picked.count))
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
            fits.append((fit.candidate.key, why))
        }

        var note = ""
        if limitHit {
            note = "GitHub's limit was reached: \(usedSaved) repo\(usedSaved == 1 ? "" : "s") used saved info. A token in Settings raises the limit."
        } else if usedSaved > 0 {
            note = "\(usedSaved) README\(usedSaved == 1 ? "" : "s") could not be read; saved info was used."
        }
        return Outcome(fits: fits, note: note)
    }

    /// Word score, fused by rank with Apple's on-device sentence embedding
    /// when this Mac has it.
    nonisolated private static func rank(_ project: String, _ candidates: [FitScorer.Candidate]) -> [FitScorer.Scored] {
        let scored = FitScorer.score(project: project, candidates: candidates)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let query = embedding.vector(for: String(project.prefix(1000))) else {
            return FitScorer.ordered(scored)
        }
        let sims = candidates.map { candidate -> Double in
            guard let v = embedding.vector(for: String(candidate.text.prefix(1000))) else { return 0 }
            return cosine(query, v)
        }
        return FitScorer.ordered(scored, embedding: sims)
    }

    nonisolated private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (sqrt(na) * sqrt(nb)) : 0
    }
}
