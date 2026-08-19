import SwiftUI
import SwiftData

/// Resolves the selected catalog project inside the inspector subtree.
struct CatalogInspectorPane: View {
    let listSelection: CatalogListSelection?
    var onSelectionChange: (CatalogListSelection?) -> Void

    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]

    var body: some View {
        Group {
            if let project = resolvedProject {
                InspectView(project: project, onDelete: { onSelectionChange(nil) })
                    .id(project.id)
            } else {
                EmptyInspectorView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var resolvedProject: ToolProject? {
        guard let id = listSelection?.projectID else { return nil }
        return allProjects.first(where: { $0.id == id })
    }
}
