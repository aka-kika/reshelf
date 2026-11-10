import SwiftUI
import SwiftData

/// Resolves the selected catalog project inside the inspector subtree.
struct CatalogInspectorPane: View {
    let listSelection: CatalogListSelection?
    /// One of her repos picked in the sidebar: the inspector adds why the
    /// selected repo fits it.
    var myRepoID: UUID? = nil
    var onSelectionChange: (CatalogListSelection?) -> Void

    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]
    @Query private var myRepos: [MyRepo]
    @Query private var repoFits: [RepoFit]

    var body: some View {
        Group {
            if let project = resolvedProject {
                InspectView(project: project, whyItFits: whyItFits(for: project),
                            onDelete: { onSelectionChange(nil) })
                    .id(project.id)
            } else {
                EmptyInspectorView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func whyItFits(for project: ToolProject) -> InspectView.WhyItFits? {
        guard let myRepoID, let repo = myRepos.first(where: { $0.id == myRepoID }) else { return nil }
        let key = GitHubRepositoryURL.dedupKey(for: project.githubURL)
        guard let fit = repoFits.first(where: { $0.myRepoID == myRepoID && $0.repoKey == key }),
              !fit.isHidden else { return nil }
        return .init(repoName: repo.displayName, why: fit.why, isNew: fit.isNew)
    }

    private var resolvedProject: ToolProject? {
        guard let id = listSelection?.projectID else { return nil }
        return allProjects.first(where: { $0.id == id })
    }
}
