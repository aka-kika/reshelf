import Foundation

/// Fills in Personal Fit from what Kika already keeps: Top Shelf and cloned
/// repos (Sift does the same with installed apps). Plain counting, no AI, so
/// the whole catalog scores in milliseconds.
///
/// Every repo casts a vote for its tags and category: Top Shelf counts 1,
/// cloned 0.5, anything else 0. A repo's fit is the average vote its tags and
/// category earned, and the stars rank that fit against the rest of the shelf.
/// A repo is in its own profile on purpose (like an installed app in Sift):
/// her own shelving is the strongest signal there is. Hand-set scores
/// (`fitScoreSetByUser`) are never touched.
@MainActor
enum FitScorer {
    private struct Profile {
        var votes: [String: Double] = [:]
        var total: [String: Int] = [:]
        var baseRate = 0.5
        /// Raw fits at the 10/30/70/90% marks: below each one, one star less.
        var cutoffs: [Double] = []
    }

    private static var profile = Profile()
    private static let migratedKey = "reshelf.fitScore.manualMigrated"
    /// How many repos' worth of "average" a thin feature is pulled towards.
    private static let smoothing = 5.0

    /// Recomputes every auto score. Returns true when anything changed (the
    /// caller saves).
    @discardableResult
    static func refresh(_ projects: [ToolProject]) -> Bool {
        var changed = migrateManualScores(projects)
        let scored = projects.filter { $0.status != .yardSale }
        profile = buildProfile(scored)

        let raw = scored.map { rawFit($0) }.sorted()
        if raw.count >= 5 {
            profile.cutoffs = [0.1, 0.3, 0.7, 0.9].map { raw[Int(Double(raw.count - 1) * $0)] }
        }
        for project in projects where !project.fitScoreSetByUser {
            let stars = autoStars(for: project)
            if project.fitScore != stars {
                project.fitScore = stars
                changed = true
            }
        }
        return changed
    }

    /// One plain sentence on why the auto score is what it is.
    static func explanation(for project: ToolProject) -> String? {
        guard !profile.total.isEmpty else { return nil }
        let prefs = features(of: project).compactMap { f -> (name: String, lean: Double)? in
            guard let (pref, weight) = preference(f) else { return nil }
            return (displayName(f, in: project), (pref - profile.baseRate) * weight)
        }
        guard !prefs.isEmpty else { return "Not enough on your shelf like this yet." }
        let liked = prefs.filter { $0.lean > 0 }.sorted { $0.lean > $1.lean }.prefix(3).map(\.name)
        let unliked = prefs.filter { $0.lean < 0 }.sorted { $0.lean < $1.lean }.prefix(3).map(\.name)
        if project.fitScore >= 4, !liked.isEmpty {
            return "Like your Top Shelf and cloned repos: \(liked.joined(separator: ", "))."
        }
        if project.fitScore <= 2, !unliked.isEmpty {
            return "You rarely keep or clone repos like this: \(unliked.joined(separator: ", "))."
        }
        return "A mixed match with what you keep."
    }

    // MARK: - Scoring

    /// Cloned-only counts half: most of the shelf is cloned, so on its own it
    /// barely tells repos apart (tested on the real catalog, 2026-09-24).
    private static func vote(_ project: ToolProject) -> Double {
        if project.status == .topShelf { return 1 }
        return CatalogCloneService.isCloned(project) ? 0.5 : 0
    }

    private static func features(of project: ToolProject) -> Set<String> {
        var result = Set(project.tags.filter(SidebarTagRanking.isUseful)
            .map { "tag:" + SidebarTagRanking.key(for: $0) })
        result.remove("tag:")
        if !project.category.isEmpty { result.insert("cat:" + project.category) }
        return result
    }

    private static func buildProfile(_ projects: [ToolProject]) -> Profile {
        var p = Profile()
        var votes = 0.0
        for project in projects {
            let v = vote(project)
            votes += v
            for f in features(of: project) {
                p.total[f, default: 0] += 1
                p.votes[f, default: 0] += v
            }
        }
        p.baseRate = projects.isEmpty ? 0.5 : votes / Double(projects.count)
        return p
    }

    /// Average vote for one feature, pulled towards the shelf average when few
    /// repos share it, plus how much evidence stands behind it.
    private static func preference(_ feature: String) -> (Double, Double)? {
        let total = profile.total[feature] ?? 0
        guard total > 0 else { return nil }
        let votes = profile.votes[feature] ?? 0
        let pref = (votes + smoothing * profile.baseRate) / (Double(total) + smoothing)
        return (pref, log(1 + Double(total)))
    }

    private static func rawFit(_ project: ToolProject) -> Double {
        var sum = 0.0, weights = 0.0
        for f in features(of: project) {
            guard let (pref, weight) = preference(f) else { continue }
            sum += pref * weight
            weights += weight
        }
        return weights > 0 ? sum / weights : profile.baseRate
    }

    private static func autoStars(for project: ToolProject) -> Int {
        guard profile.cutoffs.count == 4 else { return 3 }
        let fit = rawFit(project)
        return 1 + profile.cutoffs.filter { fit > $0 }.count
    }

    private static func displayName(_ feature: String, in project: ToolProject) -> String {
        if feature.hasPrefix("cat:") { return String(feature.dropFirst(4)) }
        let key = String(feature.dropFirst(4))
        return project.tags.first { SidebarTagRanking.key(for: $0) == key }?.lowercased() ?? key
    }

    /// Before auto-fit, a score other than the untouched default (3) could only
    /// have been set by hand. Mark those once so they're never overwritten.
    private static func migrateManualScores(_ projects: [ToolProject]) -> Bool {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return false }
        var changed = false
        for project in projects where project.fitScore != 3 && project.fitScore != 0 {
            project.fitScoreSetByUser = true
            changed = true
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
        return changed
    }
}
