import Foundation
import SwiftData

/// One of Kika's own GitHub repos, added to the sidebar's My Repos section so
/// reshelf can show which shelf repos fit it (Project fits, 10 Nov).
///
/// Fits are found when she adds the repo and again only when she asks (Find
/// Fits Again). Nothing runs on open or in the background.
@Model
final class MyRepo {
    var id: UUID = UUID()
    /// `owner/name` as GitHub spells it.
    var fullName: String = ""
    var githubURL: String = ""
    /// GitHub's one-line description, shown nowhere yet but used in the match.
    var summary: String = ""
    var addedAt: Date = Date()
    /// Sidebar order; ties break on name.
    var sortIndex: Int = 0
    /// When Find Fits last finished, and the run before it (to say what is new).
    var lastRunAt: Date?
    var previousRunAt: Date?
    /// One line about the last run when it needs saying ("GitHub's limit was
    /// reached: 6 repos used saved info"). Empty when the run went normally.
    var lastRunNote: String = ""
    /// The text the last run matched (description + cleaned README). Other
    /// runs read it to tell what all her repos share, so a shelf repo that
    /// fits every one of them is pushed down (round 2, 10 Nov).
    var matchText: String = ""
    /// What the last full run was set to (`FitScorer.runSignature`: scoring
    /// version, limit, filters). New Fits looks only at new repos
    /// while this still matches; otherwise it checks the whole shelf.
    var runSignature: String = ""
    /// Her repo's main language on GitHub ("Swift"), for Settings > Fits >
    /// Same language. Read when added, or on the first run after 1.17.0.
    var language: String = ""

    init(fullName: String, githubURL: String, summary: String = "", sortIndex: Int = 0) {
        self.id = UUID()
        self.fullName = fullName
        self.githubURL = githubURL
        self.summary = summary
        self.addedAt = Date()
        self.sortIndex = sortIndex
    }

    /// The name shown in the sidebar: the repo part of `owner/name`.
    var displayName: String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }
}

/// One shelf repo that fits one of Kika's repos. A plain id links it to its
/// `MyRepo` (like `ToolProject.folderID`), and the shelf repo is named by its
/// GitHub key (`GitHubRepositoryURL.dedupKey`), not by a catalog row id: keys
/// survive a restore and another Mac, and an agent's script can read them.
@Model
final class RepoFit {
    var id: UUID = UUID()
    var myRepoID: UUID = UUID()
    /// `owner/repo`, lowercased.
    var repoKey: String = ""
    /// Order in the list (0 first): best fit first, whichever shelf.
    var rank: Int = 0
    /// One line on why it fits, from Apple Intelligence or the shared words.
    var why: String = ""
    /// Not in the list the run before (the dot in the list).
    var isNew: Bool = false
    /// "Hide from <repo> Fits": stays hidden through later runs until shown again.
    var isHidden: Bool = false
    var foundAt: Date = Date()
    /// The fit score from its run (`FitScorer.Scored.score`): the list is
    /// ordered by it, and New Fits merges new fits in by it.
    var score: Double = 0

    init(myRepoID: UUID, repoKey: String, rank: Int, why: String, isNew: Bool, isHidden: Bool,
         score: Double = 0) {
        self.id = UUID()
        self.myRepoID = myRepoID
        self.repoKey = repoKey
        self.rank = rank
        self.why = why
        self.isNew = isNew
        self.isHidden = isHidden
        self.foundAt = Date()
        self.score = score
    }
}
