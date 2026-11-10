import Foundation

/// The matching math behind Project fits, kept free of SwiftData and the
/// network so it can be tested on plain values.
///
/// Two passes (Kika, 10 Nov): the first scores every Top Shelf and Collector
/// repo against her project from what reshelf already stores; the best 25 get
/// their README read live from GitHub and are scored again. Scoring is TF-IDF
/// cosine over words (what the two texts share, weighted by how rare a word is
/// on the shelf), optionally blended with Apple's on-device sentence
/// embeddings by rank.
enum FitScorer {
    /// How many candidates get a live README in the second pass.
    static let liveReadmeCount = 25
    /// Most fits shown for one project. Top Shelf comes first (up to
    /// `topShelfShare`), The Collector fills the rest.
    static let maxFits = 10
    static let topShelfShare = 6
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

    /// TF-IDF cosine of the project against every candidate. The document
    /// frequencies come from the candidates themselves (the shelf), so a word
    /// every repo uses ("swift" on a Swift-heavy shelf) weighs little.
    static func score(project: String, candidates: [Candidate]) -> [Scored] {
        guard !candidates.isEmpty else { return [] }
        let docs = candidates.map { termCounts(tokens($0.text)) }
        var df: [String: Int] = [:]
        for doc in docs { for term in doc.keys { df[term, default: 0] += 1 } }
        let n = Double(candidates.count)
        func idf(_ term: String) -> Double { log((n + 1) / (Double(df[term] ?? 0) + 1)) + 1 }

        // Only the project's strongest words: a long README otherwise lets
        // dozens of everyday words add up to a match.
        let allQuery = weights(termCounts(tokens(project)), idf: idf)
        let query = Dictionary(uniqueKeysWithValues: allQuery
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(queryTermLimit).map { ($0.key, $0.value) })
        let queryNorm = norm(query)
        guard queryNorm > 0 else {
            return candidates.map { Scored(candidate: $0, score: 0, sharedTerms: [], sharedCount: 0) }
        }
        return zip(candidates, docs).map { candidate, counts in
            let doc = weights(counts, idf: idf)
            let docNorm = norm(doc)
            var dot = 0.0
            var contributions: [(String, Double)] = []
            for (term, q) in query {
                if let d = doc[term] {
                    dot += q * d
                    contributions.append((term, q * d))
                }
            }
            let cosine = docNorm > 0 ? dot / (queryNorm * docNorm) : 0
            let shared = contributions.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
                .prefix(4).map(\.0)
            return Scored(candidate: candidate, score: cosine, sharedTerms: Array(shared),
                          sharedCount: contributions.count)
        }
    }

    private static func termCounts(_ tokens: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for t in tokens { counts[t, default: 0] += 1 }
        return counts
    }

    private static func weights(_ counts: [String: Int], idf: (String) -> Double) -> [String: Double] {
        var out: [String: Double] = [:]
        for (term, count) in counts {
            out[term] = (1 + log(Double(count))) * idf(term)
        }
        return out
    }

    private static func norm(_ v: [String: Double]) -> Double {
        sqrt(v.values.reduce(0) { $0 + $1 * $1 })
    }

    /// Orders by the word score, or — when sentence-embedding similarities
    /// are given (same order as `scored`) — by reciprocal-rank fusion of the
    /// two, so neither scale has to be calibrated against the other.
    static func ordered(_ scored: [Scored], embedding: [Double]? = nil) -> [Scored] {
        guard let embedding, embedding.count == scored.count else {
            return scored.sorted { $0.score == $1.score ? $0.candidate.name < $1.candidate.name : $0.score > $1.score }
        }
        let k = 30.0
        let wordRank = rankMap(scored.indices.map { scored[$0].score })
        let embRank = rankMap(embedding)
        let fused = scored.indices.map { i in 1 / (k + Double(wordRank[i])) + 1 / (k + Double(embRank[i])) }
        return scored.indices.sorted {
            fused[$0] == fused[$1] ? scored[$0].candidate.name < scored[$1].candidate.name : fused[$0] > fused[$1]
        }.map { scored[$0] }
    }

    /// Index → rank (0 = best) for a list of values, highest first.
    private static func rankMap(_ values: [Double]) -> [Int] {
        let order = values.indices.sorted { values[$0] > values[$1] }
        var ranks = Array(repeating: 0, count: values.count)
        for (rank, index) in order.enumerated() { ranks[index] = rank }
        return ranks
    }

    /// The fits shown: above `minScore`, hidden ones out, Top Shelf first
    /// (up to `topShelfShare`, more when The Collector has fewer), then The
    /// Collector, each in the order given.
    static func pick(_ ordered: [Scored], hidden: Set<String>) -> [Scored] {
        let eligible = ordered.filter {
            $0.score >= minScore && $0.sharedCount >= minSharedTerms && !hidden.contains($0.candidate.key)
        }
        let top = eligible.filter(\.candidate.isTopShelf)
        let collector = eligible.filter { !$0.candidate.isTopShelf }
        let collectorRoom = maxFits - min(top.count, topShelfShare)
        let collectorPart = Array(collector.prefix(collectorRoom))
        let topPart = Array(top.prefix(maxFits - collectorPart.count))
        return topPart + collectorPart
    }

    /// The plain why line when Apple Intelligence can't write one.
    static func fallbackWhy(_ scored: Scored) -> String {
        guard !scored.sharedTerms.isEmpty else { return "Close to your project overall." }
        return "Shares: " + scored.sharedTerms.joined(separator: ", ")
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
