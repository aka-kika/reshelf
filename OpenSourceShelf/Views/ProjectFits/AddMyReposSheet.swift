import SwiftUI
import SwiftData

/// "Add Your Repos to the Sidebar": her own GitHub repos to tick (Kika's
/// design, 10 Nov). Fits are found once for each repo added; after that only
/// when she asks.
struct AddMyReposSheet: View {
    /// Called with the repos just added (the first one gets selected).
    var onAdded: ([UUID]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [MyRepo]
    /// Without a token GitHub only lists public repos, and needs the name.
    @AppStorage("reshelf.myRepos.githubUser") private var githubUser = ""

    @State private var repos: [ProjectFitsGitHub.OwnRepo] = []
    @State private var picked: Set<String> = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var hasToken = GitHubAuth.hasToken

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Your Repos to the Sidebar")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.top, 18)
            Text("Your own GitHub repos. Fits are found when you add one, and again only when you ask.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if !hasToken {
                HStack(spacing: 8) {
                    TextField("Your GitHub user name", text: $githubUser)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(load)
                    Button("Show Repos", action: load)
                        .disabled(githubUser.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                .padding(.horizontal, 20)
                Text("Without a GitHub token only public repos show. Add one in Settings, Capture, GitHub to see private ones.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }

            TextField("Search your repos", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .disabled(repos.isEmpty)

            Divider()
            list
            Divider()

            HStack {
                if let loadError {
                    Text(loadError)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(addTitle, action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 520)
        .onAppear { if hasToken || !githubUser.isEmpty { load() } }
    }

    @ViewBuilder
    private var list: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if repos.isEmpty {
            Text(hasToken ? "No repos to show." : "Type your GitHub user name to see your public repos.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { repo in
                        row(repo)
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private func row(_ repo: ProjectFitsGitHub.OwnRepo) -> some View {
        let already = alreadyAdded.contains(repo.id)
        let isOn = already || picked.contains(repo.id)
        return HStack(spacing: 10) {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .opacity(already ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(.system(size: 13))
                if let about = repo.description, !about.isEmpty {
                    Text(about)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(already ? "in the sidebar" : (repo.isPrivate ? "private" : "public"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !already else { return }
            if picked.contains(repo.id) { picked.remove(repo.id) } else { picked.insert(repo.id) }
        }
    }

    private var alreadyAdded: Set<String> { Set(existing.map { $0.fullName.lowercased() }) }

    private var shown: [ProjectFitsGitHub.OwnRepo] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return repos }
        return repos.filter { $0.fullName.lowercased().contains(q) || ($0.description ?? "").lowercased().contains(q) }
    }

    private var addTitle: String {
        picked.count == 1 ? "Add 1 Repo" : (picked.isEmpty ? "Add" : "Add \(picked.count) Repos")
    }

    private func load() {
        isLoading = true
        loadError = nil
        let user = githubUser
        Task { @MainActor in
            do {
                repos = try await ProjectFitsGitHub.ownRepos(user: user)
            } catch {
                loadError = error.localizedDescription
                repos = []
            }
            isLoading = false
        }
    }

    private func add() {
        let chosen = repos.filter { picked.contains($0.id) }
        let added = ProjectFitsService.add(
            chosen.map { ($0.fullName, $0.htmlUrl, $0.description ?? "") }, in: modelContext)
        // Her repo's main language, for Settings > Fits > Same language.
        let languages = Dictionary(chosen.map { ($0.id, $0.language ?? "") }, uniquingKeysWith: { a, _ in a })
        for repo in added { repo.language = languages[repo.fullName.lowercased()] ?? "" }
        let ids = added.map(\.id)
        if !ids.isEmpty {
            ProjectFitsRunner.shared.run(ids, in: modelContext)
            onAdded(ids)
        }
        dismiss()
    }
}
