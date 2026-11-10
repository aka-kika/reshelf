import Foundation

/// The matching math behind Project fits, kept free of SwiftData and the
/// network so it can be tested on plain values.
///
/// Two passes (Kika, 10 Nov): the first scores every Top Shelf and Collector
/// repo against her project from what reshelf already stores; the best few
/// (the fits limit plus 10) get their README read live from GitHub and are
/// scored again. Scoring is TF-IDF cosine over words (what the two texts
/// share, weighted by how rare a word is on the shelf and among her own
/// repos), with repos that fit many of her repos pushed down. Round 2 (10
/// Nov) dropped Apple's sentence embedding: on her shelf it rated a Markdown
/// notes app closer to Sift than the uninstallers that really fit.
enum FitScorer {
    /// Bumped when the scoring changes, so the next New Fits checks
    /// the whole shelf instead of only what is new.
    static let version = 2
    /// How many fits at most (Settings > Fits). Only real fits are shown, so
    /// a list can be shorter.
    static let limitChoices = [10, 15, 20, 25]
    static let defaultLimit = 15
    static let limitKey = "reshelf.fits.limit"
    /// How many candidates get today's README in the second pass: the limit
    /// plus room for the ones that drop out once their README is read.
    static func shortlistCount(for limit: Int) -> Int { limit + 10 }
    /// What a saved list was made with. New Fits only adds new repos
    /// to a list made the same way; any change means checking all again.
    static func runSignature(limit: Int, filters: String = "") -> String {
        "v\(version) limit \(limit)" + (filters.isEmpty ? "" : " " + filters)
    }
    /// Below this TF-IDF cosine a repo does not fit, however it ranks: an
    /// empty list beats padding (Kika: "If nothing fits, say so").
    /// Calibrated on Kika's shelf (10 Nov): real fits for Sift and Kartina
    /// scored 0.09 to 0.21, single-word coincidences 0.05 to 0.08.
    static let minScore = 0.07
    /// A fit shares at least this many of the project's strong words: one
    /// shared word ("repo", "temperature") is a coincidence.
    static let minSharedTerms = 2
    /// How many of the project's words the match uses.
    static let queryTermLimit = 40
    /// How much less a word counts when every one of her repos uses it
    /// (about half). Tuned on her shelf, 10 Nov: repos listed for 3 or more
    /// of her 11 repos went from 11 to 2.
    static let ownWordPenalty = 1.5
    /// Each other repo of hers that a shelf repo also fits divides its score
    /// by (1 + this).
    static let breadthPenalty = 0.25
    /// Top Shelf's small lift (Kika: Top Shelf wins a tie, never fixed slots).
    static let topShelfLift = 1.08

    /// One shelf repo as the scorer sees it.
    struct Candidate: Equatable {
        let key: String          // GitHubRepositoryURL.dedupKey
        let name: String
        let isTopShelf: Bool
        var text: String
    }

    struct Scored: Equatable {
        let candidate: Candidate
        let score: Double
        /// The words that carried the match, strongest first (the fallback
        /// "why" when Apple Intelligence is not available).
        let sharedTerms: [String]
        /// How many of the project's words the repo shares in all.
        var sharedCount: Int = 0
        /// The word score alone, before the lifts and push-downs.
        var wordScore: Double = 0
        /// How many of her other repos it also fits.
        var breadth: Int = 0

        init(candidate: Candidate, score: Double, wordScore: Double? = nil, sharedTerms: [String],
             sharedCount: Int = 0, breadth: Int = 0) {
            self.candidate = candidate
            self.score = score
            self.wordScore = wordScore ?? score
            self.sharedTerms = sharedTerms
            self.sharedCount = sharedCount
            self.breadth = breadth
        }
    }

    // MARK: - Text

    /// README text without what only adds noise to word matching: code blocks,
    /// HTML, badge and image lines, link targets, tables' bars.
    static func cleanReadme(_ raw: String, limit: Int = 6000) -> String {
        var text = raw
        text = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: " ", options: .regularExpression)
        // [label](target) keeps the label.
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[|#*_>`~=-]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) : trimmed
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "can", "for", "from", "has", "have",
        "how", "if", "in", "into", "is", "it", "its", "of", "on", "or", "our", "so", "that",
        "the", "their", "then", "there", "this", "to", "use", "used", "using", "was", "we",
        "what", "when", "which", "will", "with", "you", "your", "all", "any", "also", "more",
        "not", "one", "out", "via", "just", "make", "makes", "like", "get", "set", "new",
        "app", "apps", "tool", "tools", "project", "projects", "repo", "repository", "open",
        "source", "github", "com", "www", "http", "https", "license", "mit", "install",
        "installation", "run", "build", "readme", "see", "please", "support",
        "copyright", "contributing", "contributors", "star", "stars", "free", "simple",
        "easy", "fast", "lightweight", "powerful", "features", "feature", "usage", "example",
        "examples", "docs", "documentation", "version", "release", "releases", "download",
        "brew", "npm", "pip", "yarn", "code", "file", "files", "do", "does", "no", "yes",
        "it's", "don't", "s", "t", "v", "e", "g", "etc", "i", "my", "me", "up", "now",
        // Plain English that says nothing about what a repo does.
        "about", "after", "again", "against", "already", "always", "am", "another", "anything",
        "around", "away", "back", "because", "been", "before", "being", "below", "best",
        "better", "between", "both", "but", "came", "come", "could", "did", "different",
        "done", "down", "during", "each", "either", "else", "enough", "even", "ever", "every",
        "everything", "few", "first", "found", "full", "give", "go", "goes", "going", "good",
        "got", "great", "had", "hand", "he", "her", "here", "him", "his", "however", "idea",
        "instead", "keep", "kept", "kind", "know", "last", "later", "least", "less", "let",
        "lets", "line", "lines", "little", "long", "look", "lot", "made", "many", "may",
        "might", "most", "much", "must", "need", "needed", "needs", "never", "next", "nothing",
        "off", "often", "once", "only", "other", "others", "over", "own", "part", "per",
        "place", "point", "put", "quick", "quickly", "rather", "real", "really", "right",
        "same", "say", "says", "second", "should", "show", "shows", "since", "small", "some",
        "something", "still", "such", "sure", "take", "takes", "than", "them", "these",
        "they", "thing", "things", "think", "those", "though", "through", "time", "times",
        "today", "too", "top", "try", "two", "under", "until", "upon", "us", "very", "want",
        "wants", "way", "ways", "well", "were", "where", "whether", "while", "who", "whole",
        "why", "within", "without", "work", "works", "would", "yet", "able", "add", "added",
        "adds", "allow", "allows", "anyone", "available", "based", "built", "call", "called",
        "change", "changes", "check", "click", "default", "end", "find", "following",
        "help", "includes", "including", "left", "list", "lists", "mode", "note",
        "notes", "opens", "option", "options", "plain", "possible", "ready",
        "simply", "start", "started", "step", "steps", "stay", "stays", "turn", "type",
        "user", "users", "value", "whatever", "word", "words", "yourself", "everyone",
        "ui", "ux", "api", "cli", "macos", "mac", "apple", "swift", "native", "local", "data",
    ]

    /// Lowercased word tokens, stop words out, a light plural trim so "agents"
    /// meets "agent". Hyphenated words count both whole and split ("menu-bar"
    /// gives "menubar", "menu", "bar").
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        let lowered = text.lowercased()
        for raw in lowered.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "-") }) {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard !word.isEmpty else { continue }
            let parts = word.split(separator: "-").map(String.init)
            var forms = parts
            if parts.count > 1 { forms.append(parts.joined()) }
            for form in forms {
                guard form.count > 1, !stopWords.contains(form),
                      !form.allSatisfy(\.isNumber) else { continue }
                out.append(stem(form))
            }
        }
        return out
    }

    private static func stem(_ word: String) -> String {
        if word.count > 4, word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") {
            return String(word.dropLast())
        }
        return word
    }

    // MARK: - Scoring

    /// One text's strongest words with their weights.
    struct Query {
        let weights: [String: Double]
        let norm: Double
    }

    /// Word weights shared by every score in one run: how rare a word is on
    /// the shelf, and how rare it is among her own repos. A word most of her
    /// repos use ("agent", "markdown", "menu bar" for Kika) says little about
    /// what makes this one different, so it counts less (round 2, 10 Nov).
    struct Weights {
        let docs: [[String: Double]]
        let docNorms: [Double]
        let shelfIDF: (String) -> Double
        let ownIDF: (String) -> Double
    }

    static func weights(candidates: [Candidate], ownTexts: [String]) -> Weights {
        let counts = candidates.map { termCounts(tokens($0.text)) }
        var df: [String: Int] = [:]
        for doc in counts { for term in doc.keys { df[term, default: 0] += 1 } }
        let n = Double(candidates.count)
        let shelfIDF: (String) -> Double = { log((n + 1) / (Double(df[$0] ?? 0) + 1)) + 1 }
        var own: [String: Int] = [:]
        for text in ownTexts { for term in Set(tokens(text)) { own[term, default: 0] += 1 } }
        let m = Double(max(ownTexts.count, 1))
        // 1 for a word only this repo has, falling towards 1/(1 + log 2) for
        // one every repo of hers has.
        let ownIDF: (String) -> Double = { term in
            let share = Double(own[term] ?? 1)
            return 1 / (1 + log(1 + (share - 1) / max(m - 1, 1)) * ownWordPenalty)
        }
        let docs = counts.map { weigh($0, idf: shelfIDF) }
        return Weights(docs: docs, docNorms: docs.map(norm), shelfIDF: shelfIDF, ownIDF: ownIDF)
    }

    static func query(_ text: String, _ w: Weights) -> Query {
        var all = weigh(termCounts(tokens(text)), idf: w.shelfIDF)
        for (term, value) in all { all[term] = value * w.ownIDF(term) }
        // Only the project's strongest words: a long README otherwise lets
        // dozens of everyday words add up to a match.
        let top = Dictionary(uniqueKeysWithValues: all
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(queryTermLimit).map { ($0.key, $0.value) })
        return Query(weights: top, norm: norm(top))
    }

    /// TF-IDF cosine of one query against candidate `index`, with the words
    /// that carried it.
    static func cosine(_ q: Query, _ w: Weights, _ index: Int) -> (score: Double, shared: [String], count: Int) {
        let doc = w.docs[index]
        let docNorm = w.docNorms[index]
        guard q.norm > 0, docNorm > 0 else { return (0, [], 0) }
        var dot = 0.0
        var contributions: [(String, Double)] = []
        for (term, value) in q.weights {
            if let d = doc[term] {
                dot += value * d
                contributions.append((term, value * d))
            }
        }
        let shared = contributions.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }.prefix(4).map(\.0)
        return (dot / (q.norm * docNorm), Array(shared), contributions.count)
    }

    /// Scores every candidate against her project.
    ///
    /// - `others`: her other repos' texts. A shelf repo that fits many of
    ///   them is generic for her (a Markdown notes app fits every repo of hers
    ///   that mentions Markdown), so it is pushed down and the specific fits
    ///   win. It is never removed for that alone.
    /// - Top Shelf gets a small lift: it wins a near tie, never a fixed slot.
    static func score(project: String, others: [String] = [], candidates: [Candidate]) -> [Scored] {
        guard !candidates.isEmpty else { return [] }
        let w = weights(candidates: candidates, ownTexts: [project] + others)
        let q = query(project, w)
        let otherQueries = others.map { query($0, w) }.filter { $0.norm > 0 }
        return candidates.indices.map { i in
            let c = cosine(q, w, i)
            var breadth = 0
            if c.score >= minScore {
                for other in otherQueries {
                    let o = cosine(other, w, i)
                    if o.score >= minScore, o.count >= minSharedTerms { breadth += 1 }
                }
            }
            var final = c.score / (1 + breadthPenalty * Double(breadth))
            if candidates[i].isTopShelf { final *= topShelfLift }
            return Scored(candidate: candidates[i], score: final, wordScore: c.score,
                          sharedTerms: c.shared, sharedCount: c.count, breadth: breadth)
        }
    }

    private static func termCounts(_ tokens: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for t in tokens { counts[t, default: 0] += 1 }
        return counts
    }

    private static func weigh(_ counts: [String: Int], idf: (String) -> Double) -> [String: Double] {
        var out: [String: Double] = [:]
        for (term, count) in counts {
            out[term] = (1 + log(Double(count))) * idf(term)
        }
        return out
    }

    private static func norm(_ v: [String: Double]) -> Double {
        sqrt(v.values.reduce(0) { $0 + $1 * $1 })
    }

    /// Best first by the final score; a tie goes to Top Shelf, then the name.
    static func ordered(_ scored: [Scored]) -> [Scored] {
        scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.candidate.isTopShelf != $1.candidate.isTopShelf { return $0.candidate.isTopShelf }
            return $0.candidate.name < $1.candidate.name
        }
    }

    /// Does this candidate fit at all? The word score must clear the cut and
    /// share at least two strong words: one shared word is a coincidence.
    static func fits(_ scored: Scored) -> Bool {
        scored.wordScore >= minScore && scored.sharedCount >= minSharedTerms
    }

    /// The fits shown: only real fits (an empty list beats padding), hidden
    /// ones out, best first, at most `limit`. Fewer is fine.
    static func pick(_ scored: [Scored], hidden: Set<String>, limit: Int = defaultLimit) -> [Scored] {
        Array(ordered(scored.filter { fits($0) && !hidden.contains($0.candidate.key) }).prefix(limit))
    }

    /// The plain why line when Apple Intelligence can't write one.
    static func fallbackWhy(_ scored: Scored) -> String {
        guard !scored.sharedTerms.isEmpty else { return "Close to your project overall." }
        return "Shares: " + scored.sharedTerms.joined(separator: ", ")
    }
}

/// New Fits (round 2, Kika: "it should not reanalyze all, it should
/// analyze the new reshelfs"): only shelf repos added or changed since the
/// last run are scored, then merged into the saved list by score.
enum FitIncremental {
    /// A fit on the saved list.
    struct Saved: Equatable, Sendable {
        let key: String
        let why: String
        let score: Double
        let isTopShelf: Bool
        /// Kept with "Keep" after a run pushed it off: later runs keep it.
        var isPinned: Bool = false
    }

    /// The list after the limit, and the saved fits it pushed off ("2 older
    /// fits made room", Kika, 10 Nov).
    struct Limited: Equatable {
        let list: [Saved]
        let madeRoom: [Saved]
    }

    static func ordered(_ items: [Saved]) -> [Saved] {
        items.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.isTopShelf != $1.isTopShelf { return $0.isTopShelf }
            return $0.key < $1.key
        }
    }

    /// Kept fits stay first in line for a place; the best of the rest fill
    /// up to `limit`. What was on the saved list (`previous`) and no longer
    /// has a place made room.
    static func applyLimit(_ candidates: [Saved], pinned: Set<String>, previous: Set<String>,
                           limit: Int) -> Limited {
        var seen = Set<String>()
        let sorted = ordered(candidates).filter { seen.insert($0.key).inserted }
        let kept = sorted.filter { pinned.contains($0.key) }
        let room = max(limit - kept.count, 0)
        let chosen = Set(kept.map(\.key) + sorted.filter { !pinned.contains($0.key) }.prefix(room).map(\.key))
        return Limited(list: sorted.filter { chosen.contains($0.key) },
                       madeRoom: sorted.filter { !chosen.contains($0.key) && previous.contains($0.key) })
    }

    /// Keys of shelf repos added to the shelf, or changed upstream as far as
    /// reshelf knows, after `since`.
    static func changed(_ items: [(key: String, added: Date, updated: Date?)], since: Date) -> Set<String> {
        Set(items.filter { $0.added > since || ($0.updated ?? .distantPast) > since }.map(\.key))
    }

    /// The saved fits that still stand (on the shelf, not re-scored this run,
    /// or kept with Keep) plus the new ones, best first, at most `limit`.
    /// Ties: Top Shelf first.
    static func merge(saved: [Saved], new: [Saved], changed: Set<String>, onShelf: Set<String>,
                      limit: Int) -> [Saved] {
        mergeLimited(saved: saved, new: new, changed: changed, onShelf: onShelf, limit: limit).list
    }

    static func mergeLimited(saved: [Saved], new: [Saved], changed: Set<String>, onShelf: Set<String>,
                             limit: Int) -> Limited {
        let newKeys = Set(new.map(\.key))
        let pinned = Set(saved.filter(\.isPinned).map(\.key))
        let kept = saved.filter {
            onShelf.contains($0.key) && !newKeys.contains($0.key) && (!changed.contains($0.key) || $0.isPinned)
        }
        let fresh = new.map { item -> Saved in
            var copy = item
            copy.isPinned = pinned.contains(item.key)
            return copy
        }
        return applyLimit(kept + fresh, pinned: pinned, previous: Set(saved.map(\.key)), limit: limit)
    }
}

/// How a new run's list meets the saved one (Kika: "it save whats listed
/// before, what hidden from list").
enum FitMerge {
    struct Row: Equatable {
        let key: String
        var rank: Int
        var why: String
        var isNew: Bool
        var isHidden: Bool
        var score: Double = 0
        var isPinned: Bool = false
        var isBumped: Bool = false
    }

    /// Hidden rows always stay (hidden). A fit is new when its repo was not in
    /// the saved list at all — shown or hidden. Saved fits that did not come
    /// back are dropped. The first run of a project marks nothing new: with no
    /// list before it, every row would carry the dot.
    static func merge(previous: [Row], found: [(key: String, why: String)], isFirstRun: Bool) -> [Row] {
        let hidden = previous.filter(\.isHidden)
        let hiddenKeys = Set(hidden.map(\.key))
        let known = Set(previous.map(\.key))
        var rows: [Row] = []
        for (index, fit) in found.enumerated() where !hiddenKeys.contains(fit.key) {
            rows.append(Row(key: fit.key, rank: index, why: fit.why,
                            isNew: !isFirstRun && !known.contains(fit.key), isHidden: false))
        }
        return rows + hidden
    }
}

/// What reshelf's GitHub metadata store knows about one shelf repo, by its
/// `dedupKey`. The app fills it from `IntelligenceDatabase` at launch; tests
/// set it by hand.
struct RepoFacts: Equatable, Sendable {
    var language: String = ""
    var isArchived: Bool = false
    var pushedAt: Date?
    var license: String = ""
    var topics: [String] = []
}

/// Settings > Fits (Kika, round 2): the same filters for every one of her
/// repos. They apply when Find Fits runs (so the limit fills with repos that
/// pass) and to the saved list on screen (so turning one on works at once).
struct FitFilters: Codable, Equatable, Sendable {
    enum Updated: String, Codable, CaseIterable, Identifiable, Sendable {
        case any, lastYear, sixMonths, threeMonths

        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return "Any time"
            case .lastYear: return "Last year"
            case .sixMonths: return "Last 6 months"
            case .threeMonths: return "Last 3 months"
            }
        }
        var months: Int? {
            switch self {
            case .any: return nil
            case .lastYear: return 12
            case .sixMonths: return 6
            case .threeMonths: return 3
            }
        }
    }

    /// Only shelf repos in her repo's main language (each of her repos uses
    /// its own, from GitHub).
    var sameLanguage = false
    var updated: Updated = .any
    /// Leave out GPL and AGPL (strong copyleft). LGPL stays.
    var hideStrongCopyleft = false
    var hideArchived = false

    init(sameLanguage: Bool = false, updated: Updated = .any, hideStrongCopyleft: Bool = false,
         hideArchived: Bool = false) {
        self.sameLanguage = sameLanguage
        self.updated = updated
        self.hideStrongCopyleft = hideStrongCopyleft
        self.hideArchived = hideArchived
    }

    /// Missing keys (a file from another version) read as off.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sameLanguage = try c.decodeIfPresent(Bool.self, forKey: .sameLanguage) ?? false
        updated = (try? c.decodeIfPresent(Updated.self, forKey: .updated)) ?? .any
        hideStrongCopyleft = try c.decodeIfPresent(Bool.self, forKey: .hideStrongCopyleft) ?? false
        hideArchived = try c.decodeIfPresent(Bool.self, forKey: .hideArchived) ?? false
    }

    /// Plain words for the Settings list and the agents' fits command.
    var summary: String {
        var parts: [String] = []
        if sameLanguage { parts.append("same language only") }
        if let months = updated.months { parts.append(months == 12 ? "updated in the last year" : "updated in the last \(months) months") }
        if hideStrongCopyleft { parts.append("no GPL or AGPL") }
        if hideArchived { parts.append("no archived repos") }
        return parts.isEmpty ? "no filters" : parts.joined(separator: ", ")
    }

    static let sameLanguageKey = "reshelf.fits.sameLanguage"
    static let updatedKey = "reshelf.fits.updated"
    static let hideStrongCopyleftKey = "reshelf.fits.hideGPL"
    static let hideArchivedKey = "reshelf.fits.hideArchived"

    static func current(_ defaults: UserDefaults = .standard) -> FitFilters {
        FitFilters(sameLanguage: defaults.bool(forKey: sameLanguageKey),
                   updated: Updated(rawValue: defaults.string(forKey: updatedKey) ?? "") ?? .any,
                   hideStrongCopyleft: defaults.bool(forKey: hideStrongCopyleftKey),
                   hideArchived: defaults.bool(forKey: hideArchivedKey))
    }

    var isActive: Bool { self != FitFilters() }

    /// For `FitScorer.runSignature`: empty when no filter is on.
    var signature: String {
        var parts: [String] = []
        if sameLanguage { parts.append("same-language") }
        if updated != .any { parts.append("updated-\(updated.rawValue)") }
        if hideStrongCopyleft { parts.append("no-gpl") }
        if hideArchived { parts.append("no-archived") }
        return parts.joined(separator: " ")
    }

    /// GPL-2.0, GPL-3.0, AGPL-3.0 and their "-only"/"-or-later" forms; not LGPL.
    static func isStrongCopyleft(_ license: String) -> Bool {
        let upper = license.uppercased()
        return upper.contains("GPL") && !upper.contains("LGPL")
    }

    /// Does a shelf repo pass? Unknown facts fail a filter that needs them
    /// (no language or date known), except her own language: if GitHub names
    /// none for her repo, the language filter has nothing to compare and lets
    /// everything through.
    func allows(projectLanguage: String, language: String, isArchived: Bool, license: String,
                updated: Date?, now: Date = Date()) -> Bool {
        if sameLanguage, !projectLanguage.isEmpty,
           language.caseInsensitiveCompare(projectLanguage) != .orderedSame { return false }
        if hideArchived, isArchived { return false }
        if hideStrongCopyleft, Self.isStrongCopyleft(license) { return false }
        if let months = self.updated.months {
            guard let updated,
                  let cutoff = Calendar(identifier: .gregorian).date(byAdding: .month, value: -months, to: now),
                  updated >= cutoff else { return false }
        }
        return true
    }

    /// The same check for a shelf repo, from what reshelf stores about it.
    func allows(projectLanguage: String, facts: RepoFacts?, license: String, lastUpdated: Date?,
                now: Date = Date()) -> Bool {
        allows(projectLanguage: projectLanguage, language: facts?.language ?? "",
               isArchived: facts?.isArchived ?? false,
               license: license.isEmpty ? (facts?.license ?? "") : license,
               updated: lastUpdated ?? facts?.pushedAt, now: now)
    }
}

/// Everything Settings > Fits sets: the filters and the most fits. The main
/// one lives in UserDefaults; one of her repos can have its own (right-click
/// > Filter), saved as JSON in `MyRepo.fitSettingsJSON` (Kika, 10 Nov).
struct FitSettings: Codable, Equatable, Sendable {
    var filters = FitFilters()
    var limit = FitScorer.defaultLimit

    init(filters: FitFilters = FitFilters(), limit: Int = FitScorer.defaultLimit) {
        self.filters = filters
        self.limit = limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filters = (try? c.decodeIfPresent(FitFilters.self, forKey: .filters)) ?? FitFilters()
        let stored = (try? c.decodeIfPresent(Int.self, forKey: .limit)) ?? FitScorer.defaultLimit
        limit = FitScorer.limitChoices.contains(stored) ? stored : FitScorer.defaultLimit
    }

    /// Settings > Fits.
    static func main(_ defaults: UserDefaults = .standard) -> FitSettings {
        let stored = defaults.integer(forKey: FitScorer.limitKey)
        return FitSettings(filters: FitFilters.current(defaults),
                           limit: FitScorer.limitChoices.contains(stored) ? stored : FitScorer.defaultLimit)
    }

    /// A repo's own settings, or nil when it uses the main ones ("" or unreadable).
    static func decode(_ json: String) -> FitSettings? {
        guard !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(FitSettings.self, from: Data(json.utf8))
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// What one repo uses: its own settings, or the main ones.
    static func resolved(ownJSON: String, main: FitSettings) -> FitSettings {
        decode(ownJSON) ?? main
    }

    var summary: String { "\(filters.summary), at most \(limit)" }
}
