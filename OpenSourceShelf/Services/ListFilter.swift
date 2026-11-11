import Foundation

/// The Language filter next to Sort (round 3, Kika 11 Nov: "a dropdown like
/// GitHub's", with "UI only" in the same list). One setting for every list,
/// like Sort; it narrows what the sidebar, search or fits already picked.
/// Languages come from GitHub's metadata reshelf saved (`RepoFacts`).
struct ListFilter: Equatable {
    static let languageKey = "reshelf.listLanguage"
    static let uiOnlyKey = "reshelf.listUIOnly"

    /// "" = any language.
    var language: String = ""
    var uiOnly: Bool = false

    var isActive: Bool { !language.isEmpty || uiOnly }

    /// The header and empty-state name: "Swift", "UI", "Swift UI".
    var title: String {
        [language, uiOnly ? "UI" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// GitHub's main language for a shelf repo, or "" when reshelf has none.
    static func language(of project: ToolProject, facts: [String: RepoFacts]) -> String {
        guard !project.githubURL.isEmpty else { return "" }
        return facts[GitHubRepositoryURL.cachedDedupKey(for: project.githubURL)]?.language ?? ""
    }

    /// The languages in a list, most repos first, then by name. The picked
    /// one stays in the menu (with 0) when this list has none of it.
    static func counts(_ projects: [ToolProject], facts: [String: RepoFacts],
                       keeping picked: String = "") -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for project in projects {
            let lang = language(of: project, facts: facts)
            guard !lang.isEmpty else { continue }
            counts[lang.lowercased(), default: 0] += 1
            if spelling[lang.lowercased()] == nil { spelling[lang.lowercased()] = lang }
        }
        // The picked one keeps its own spelling (the menu's tick matches it
        // exactly), and stays listed with 0 when this list has none.
        if !picked.isEmpty {
            if counts[picked.lowercased()] == nil { counts[picked.lowercased()] = 0 }
            spelling[picked.lowercased()] = picked
        }
        return counts.map { (name: spelling[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// Everything the list header needs, in one pass with one key lookup per
    /// repo (review: four passes per redraw re-read every link).
    struct Outcome {
        var visible: [ToolProject] = []
        /// The languages among the repos UI Only lets through.
        var languages: [(name: String, count: Int)] = []
        /// UI-marked repos among those the language lets through.
        var uiCount = 0
    }

    func evaluate(_ projects: [ToolProject], facts: [String: RepoFacts]) -> Outcome {
        var out = Outcome()
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for project in projects {
            let lang = Self.language(of: project, facts: facts)
            let langOK = language.isEmpty || lang.caseInsensitiveCompare(language) == .orderedSame
            let uiOK = !uiOnly || project.likesUI
            if langOK, uiOK { out.visible.append(project) }
            if langOK, project.likesUI { out.uiCount += 1 }
            if uiOK, !lang.isEmpty {
                counts[lang.lowercased(), default: 0] += 1
                if spelling[lang.lowercased()] == nil { spelling[lang.lowercased()] = lang }
            }
        }
        if !language.isEmpty {
            if counts[language.lowercased()] == nil { counts[language.lowercased()] = 0 }
            spelling[language.lowercased()] = language
        }
        out.languages = counts.map { (name: spelling[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return out
    }

    func apply(_ projects: [ToolProject], facts: [String: RepoFacts]) -> [ToolProject] {
        guard isActive else { return projects }
        return projects.filter { project in
            if uiOnly, !project.likesUI { return false }
            if !language.isEmpty,
               Self.language(of: project, facts: facts).caseInsensitiveCompare(language) != .orderedSame {
                return false
            }
            return true
        }
    }
}
