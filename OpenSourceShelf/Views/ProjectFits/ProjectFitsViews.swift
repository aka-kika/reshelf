import SwiftUI
import SwiftData

/// What the project list needs to show one of Kika's repos and its fits.
/// Built once per list body from the loaded queries.
struct FitsListModel {
    let repo: MyRepo
    /// Shelf rows in list order: best fit first, whichever shelf (Kika, round
    /// 2: a better Collector fit beats a weaker Top Shelf one). Each row
    /// names its shelf instead of a heading.
    let projects: [ToolProject]
    let newIDs: Set<UUID>
    let hiddenCount: Int
    /// Saved fits that Settings > Fits leaves out right now.
    let filteredCount: Int
    /// Saved fits the last run pushed off to make room (best first).
    let madeRoom: [ToolProject]
    /// The limit this list uses (Keep needs it).
    let limit: Int
    /// Fits shown before the search narrows them (the header counts these).
    let fitCount: Int
    /// A search is narrowing the list.
    let isSearching: Bool

    init(repo: MyRepo, fits: [RepoFit], allProjects: [ToolProject], search: String,
         filters: FitFilters = FitFilters(), limit: Int = .max, facts: [String: RepoFacts] = [:],
         now: Date = Date()) {
        self.repo = repo
        let byKey = Self.byKey(allProjects)
        let mine = fits.filter { $0.myRepoID == repo.id }
        hiddenCount = mine.filter(\.isHidden).count
        let passing = Self.shown(mine, byKey: byKey, repo: repo, filters: filters, limit: limit, facts: facts,
                                 now: now)
        filteredCount = mine.filter { !$0.isHidden && !$0.isBumped && byKey[$0.repoKey] != nil }.count
            - passing.count
        madeRoom = mine.filter { $0.isBumped && !$0.isHidden }.sorted { $0.score > $1.score }
            .compactMap { byKey[$0.repoKey] }
        self.limit = limit
        fitCount = passing.count
        isSearching = !search.isEmpty
        var rows: [ToolProject] = []
        var newIDs = Set<UUID>()
        for (fit, project) in passing {
            if !search.isEmpty, !project.matchesSearch(search) { continue }
            rows.append(project)
            if fit.isNew { newIDs.insert(project.id) }
        }
        projects = rows
        self.newIDs = newIDs
    }

    static func byKey(_ projects: [ToolProject]) -> [String: ToolProject] {
        ProjectFitsService.byKey(projects)
    }

    /// The fits shown for one repo, in list order: not hidden, still on the
    /// catalog, passing Settings > Fits. The sidebar count uses it too.
    static func shown(_ fits: [RepoFit], byKey: [String: ToolProject], repo: MyRepo, filters: FitFilters,
                      limit: Int = .max, facts: [String: RepoFacts], now: Date = Date()) -> [(RepoFit, ToolProject)] {
        let passing = fits.filter { $0.myRepoID == repo.id && !$0.isHidden && !$0.isBumped }
            .sorted { $0.rank < $1.rank }
            .compactMap { fit -> (RepoFit, ToolProject)? in
                guard let project = byKey[fit.repoKey],
                      filters.allows(projectLanguage: repo.language, facts: facts[fit.repoKey],
                                     license: project.license, lastUpdated: project.lastUpdatedDate, now: now)
                else { return nil }
                return (fit, project)
            }
        // A lower limit shows at once; a higher one fills on the next run.
        return Array(passing.prefix(limit))
    }

    /// "4 fits · last run 10 Nov, 18:40"
    var subtitle: String {
        guard repo.lastRunAt != nil else { return "Not run yet" }
        // The search narrows the rows, not the fits (90b8: "0 fits").
        let count = fitCount
        var parts = [isSearching ? "\(projects.count) of \(count) fits match"
                                 : "\(count) fit\(count == 1 ? "" : "s")"]
        if let last = repo.lastRunAt {
            parts.append("last run " + last.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
        }
        return parts.joined(separator: " · ")
    }

    /// Footer: what is new and what is hidden, plus a run note if any.
    var footer: String {
        var parts = [subtitle]
        if !newIDs.isEmpty { parts.append("\(newIDs.count) new since the run before") }
        if hiddenCount > 0 { parts.append("\(hiddenCount) hidden") }
        if filteredCount > 0 { parts.append("\(filteredCount) left out by Fits filters") }
        if !repo.lastRunNote.isEmpty { parts.append(repo.lastRunNote) }
        return parts.joined(separator: " · ")
    }
}

/// A failed run over a repo that already has a list: the saved list stays
/// and this says why the run did not replace it (90b8: it was silent).
struct FitsFailureBanner: View {
    let repoName: String
    let failure: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Couldn't find new fits for \(repoName): \(failure) The saved list is unchanged.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Dismiss", action: onDismiss)
                .font(.system(size: 10))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }
}

/// The list area for one of her repos when there is no list to show: never
/// run, running, nothing fits, or the run failed.
struct FitsEmptyState: View {
    let repo: MyRepo
    let progress: ProjectFitsRunner.Progress?
    let failure: String?
    let onFind: () -> Void
    var onCheckAll: (() -> Void)? = nil
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                Text(progressText(progress))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .frame(width: 220)
                } else {
                    ProgressView().controlSize(.small)
                }
                Button("Stop", action: onStop)
                    .controlSize(.small)
            } else {
                Group {
                    if repo.lastRunAt == nil {
                        GitHubMarkIcon(size: 28)
                    } else {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 28))
                    }
                }
                .foregroundStyle(.secondary.opacity(0.35))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                HStack(spacing: 8) {
                    Button(repo.lastRunAt == nil ? "Find Fits" : "New Fits", action: onFind)
                    if repo.lastRunAt != nil, let onCheckAll {
                        Button("Analyze All Fits", action: onCheckAll)
                    }
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func progressText(_ p: ProjectFitsRunner.Progress) -> String {
        p.total > 0 ? "\(p.step): \(min(p.done + 1, p.total)) of \(p.total)" : p.step
    }

    private var title: String {
        if failure != nil { return "Couldn't find fits for \(repo.displayName)" }
        if repo.lastRunAt == nil { return "Find what on your shelf fits \(repo.displayName)" }
        return "Nothing on your shelf fits \(repo.displayName)"
    }

    private var message: String {
        if let failure { return failure }
        if repo.lastRunAt == nil {
            return "reshelf reads its README and compares it with your Top Shelf and The Collector. It runs only when you press Find Fits."
        }
        return "Nothing came close on the last run. Save more repos, or run it again after the README changes."
    }
}

/// Her hidden fits for one repo, each with Show Again.
struct HiddenFitsSheet: View {
    let repoID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var fits: [RepoFit]
    @Query private var projects: [ToolProject]
    @Query private var repos: [MyRepo]

    var body: some View {
        let repo = repos.first { $0.id == repoID }
        let hidden = fits.filter { $0.myRepoID == repoID && $0.isHidden }.sorted { $0.rank < $1.rank }
        VStack(alignment: .leading, spacing: 0) {
            Text("Hidden from \(repo?.displayName ?? "this repo")")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.top, 16)
            Text("They stay hidden through later runs until you show them again.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 10)
            Divider()
            if hidden.isEmpty {
                Text("Nothing is hidden.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(hidden) { fit in
                            HStack {
                                Text(name(of: fit.repoKey))
                                    .font(.system(size: 13))
                                Spacer()
                                Button("Show Again") {
                                    ProjectFitsService.setHidden(false, repoKey: fit.repoKey, repoID: repoID,
                                                                 in: modelContext)
                                }
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 380)
    }

    private func name(of key: String) -> String {
        projects.first { GitHubRepositoryURL.dedupKey(for: $0.githubURL) == key }?.name ?? key
    }
}

/// A long sidebar list folded to its first rows, with the picked row kept
/// visible past the cut (My Repos: first 5, then "Show 3 more").
enum SidebarFold {
    static func visible<T>(_ items: [T], limit: Int, showAll: Bool, keep: (T) -> Bool) -> [T] {
        guard !showAll, items.count > limit else { return items }
        let shown = Array(items.prefix(limit))
        return shown + items.dropFirst(limit).filter(keep).prefix(1)
    }
}

/// The GitHub mark for her own repos (Kika, round 2: "lets use the github
/// icon instead of hammer"). The same bundled mono PDF the About tab uses,
/// as a template image so it takes the sidebar's grey like the SF Symbols.
struct GitHubMarkIcon: View {
    var size: CGFloat = 13

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "social-github", withExtension: "pdf", subdirectory: "SocialIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size - 1))
        }
    }
}

/// Under a fits list after a run pushed saved fits off: "2 older fits made
/// room: Mantis, Folio. Show". Show lists them in place, each with Keep.
struct MadeRoomRow: View {
    let repoID: UUID
    let projects: [ToolProject]
    let limit: Int
    @Environment(\.modelContext) private var modelContext
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(isOpen ? "Hide" : "Show") {
                    withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
            if isOpen {
                ForEach(projects) { project in
                    HStack {
                        Text(project.name)
                            .font(.system(size: 12))
                        Text(project.status.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Keep") {
                            ProjectFitsService.keep(GitHubRepositoryURL.dedupKey(for: project.githubURL),
                                                    repoID: repoID, limit: limit, in: modelContext)
                        }
                        .controlSize(.small)
                        .help("Back on the list for good; the weakest other fit makes room")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var summary: String {
        let names = projects.prefix(3).map(\.name).joined(separator: ", ")
        let more = projects.count > 3 ? " and \(projects.count - 3) more" : ""
        return "\(projects.count) older fit\(projects.count == 1 ? "" : "s") made room: \(names)\(more)."
    }
}
