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

    init(repo: MyRepo, fits: [RepoFit], allProjects: [ToolProject], search: String) {
        self.repo = repo
        var byKey: [String: ToolProject] = [:]
        for project in allProjects where !project.githubURL.isEmpty {
            byKey[GitHubRepositoryURL.dedupKey(for: project.githubURL)] = project
        }
        let mine = fits.filter { $0.myRepoID == repo.id }
        hiddenCount = mine.filter(\.isHidden).count
        let shown = mine.filter { !$0.isHidden }.sorted { $0.rank < $1.rank }
        var rows: [ToolProject] = []
        var newIDs = Set<UUID>()
        for fit in shown {
            guard let project = byKey[fit.repoKey] else { continue }
            if !search.isEmpty, !project.matchesSearch(search) { continue }
            rows.append(project)
            if fit.isNew { newIDs.insert(project.id) }
        }
        projects = rows
        self.newIDs = newIDs
    }

    /// "4 fits · last run 10 Nov, 18:40"
    var subtitle: String {
        guard repo.lastRunAt != nil else { return "Not run yet" }
        let count = projects.count
        var parts = ["\(count) fit\(count == 1 ? "" : "s")"]
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
        if !repo.lastRunNote.isEmpty { parts.append(repo.lastRunNote) }
        return parts.joined(separator: " · ")
    }
}

/// The list area for one of her repos when there is no list to show: never
/// run, running, nothing fits, or the run failed.
struct FitsEmptyState: View {
    let repo: MyRepo
    let progress: ProjectFitsRunner.Progress?
    let failure: String?
    let onFind: () -> Void
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
                Image(systemName: repo.lastRunAt == nil ? "hammer" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.35))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button(repo.lastRunAt == nil ? "Find Fits" : "Find Fits Again", action: onFind)
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
