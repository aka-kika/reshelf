import SwiftUI
import SwiftData

private struct SidebarFilterCounts {
    private var counts: [SidebarItem: Int] = [:]

    init(projects: [ToolProject]) {
        var map: [SidebarItem: Int] = [:]
        for item in SidebarItem.sidebarCatalogItems {
            map[item] = projects.filter { item.matchesCatalogFilter($0) }.count
        }
        counts = map
    }

    func count(for item: SidebarItem) -> Int {
        counts[item, default: 0]
    }
}

struct SidebarView: View {
    @Binding var selection: ShelfSelection?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]
    @Query(sort: \CatalogFolder.sortIndex) private var folders: [CatalogFolder]

    @State private var renameTarget: CatalogFolder?
    @State private var deleteTarget: CatalogFolder?
    @State private var draftName = ""

    /// Computed (not cached) so counts refresh on any catalog change — including a
    /// project moving between shelves, which changes status but not the count.
    private var filterCounts: SidebarFilterCounts {
        SidebarFilterCounts(projects: allProjects)
    }

    var body: some View {
        // Build the counts once per render (the struct rebuilds on each access).
        let counts = filterCounts
        let categories = SidebarItem.sidebarCategoryItems.filter {
            counts.count(for: $0) > 0 || selection == .builtin($0)
        }
        return VStack(spacing: 0) {
            // Leading inset clears the traffic lights, which share this row now
            // that the header is the title bar.
            AlignedSplitColumnHeader(leadingInset: ShelfLayout.trafficLightHeaderInset) {
                ReshelfBrandHeader()
            }

            List(selection: $selection) {
                Section(SidebarSection.library.rawValue) {
                    SidebarRow(item: .allProjects, count: counts.count(for: .allProjects))
                    SidebarRow(item: .topShelf, count: counts.count(for: .topShelf))
                    SidebarRow(item: .collector, count: counts.count(for: .collector))
                    SidebarRow(item: .yardSale, count: counts.count(for: .yardSale))
                    SidebarRow(item: .cloned, count: counts.count(for: .cloned))
                }

                // Only when folders exist — an empty heading would be noise on a
                // fresh install, and folders are opt-in by nature.
                if !folders.isEmpty {
                    Section(SidebarSection.folders.rawValue) {
                        ForEach(folders) { folder in
                            FolderSidebarRow(
                                folder: folder,
                                count: memberCount(of: folder)
                            )
                            .contextMenu {
                                Button("Rename…") { renameTarget = folder }
                                Button("Delete Folder…") { deleteTarget = folder }
                            }
                        }
                    }
                }

                if !categories.isEmpty {
                    Section(SidebarSection.categories.rawValue) {
                        ForEach(categories) { item in
                            SidebarRow(item: item, count: counts.count(for: item))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .listSectionSeparator(.hidden, edges: .top)
            .scrollContentBackground(.hidden)
            // Top breathing room tuned so the first sidebar row aligns with the
            // first row of the main list (measured 3pt higher otherwise) while the
            // header divider stays aligned with the list/inspector dividers.
            .contentMargins(.top, 11, for: .scrollContent)
            .alert("Rename Folder", isPresented: presenting($renameTarget)) {
                TextField("Name", text: $draftName)
                Button("Rename") {
                    if let folder = renameTarget {
                        CatalogFolderService.rename(folder, to: draftName, in: modelContext)
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .onChange(of: renameTarget) { _, folder in
                draftName = folder?.name ?? ""
            }
            .alert("Delete Folder?", isPresented: presenting($deleteTarget)) {
                Button("Delete Folder", role: .destructive) {
                    if let folder = deleteTarget {
                        // Never leave the list filtered by a folder that no
                        // longer exists.
                        if selection == .folder(folder.id) {
                            selection = .builtin(.allProjects)
                        }
                        CatalogFolderService.delete(folder, in: modelContext)
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                if let folder = deleteTarget {
                    let count = CatalogFolderService.projectCount(for: folder, in: modelContext)
                    Text("\(count) project\(count == 1 ? "" : "s") will no longer be grouped. Nothing is deleted — they keep their shelf, their clone and their notes.")
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // The sidebar/list split divider: NavigationSplitView's own divider
        // renders zero-width on macOS 26+, so draw the same 1px separatorColor
        // hairline the inspector's ResizeDivider uses — full height, flush with
        // the sidebar's trailing edge.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .ignoresSafeArea()
        }
        // The header row IS the title bar: lay the column out from the window's
        // top edge instead of below the system title-bar inset. All three columns
        // do this, so their header dividers align by construction — no measured
        // nudge constants (which broke whenever macOS changed its insets).
        .ignoresSafeArea(.container, edges: .top)
        .hidesTopScrollEdgeEffect()
    }

    /// Counted from the already-loaded `@Query` rather than a fetch, so a row
    /// updates the moment a project's folder changes.
    private func memberCount(of folder: CatalogFolder) -> Int {
        allProjects.filter { $0.folderID == folder.id }.count
    }

    /// `.alert(isPresented:)` wants a Bool; the state that matters is which
    /// folder. Dismissing clears the target.
    private func presenting<T>(_ target: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { target.wrappedValue != nil },
            set: { if !$0 { target.wrappedValue = nil } }
        )
    }
}

/// A folder row: a filter like any other, distinguished by the folder icon.
/// Deliberately not expandable — selecting it already shows exactly its members,
/// so a tree would list the same names twice.
private struct FolderSidebarRow: View {
    let folder: CatalogFolder
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .frame(width: 20)
                .font(.system(size: 13))
            Text(folder.name)
                .font(.system(size: 13))
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .padding(.vertical, 2)
        .tag(ShelfSelection.folder(folder.id))
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    var count: Int?

    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .frame(width: 20)
                .font(.system(size: 13))
            Text(item.title)
                .font(.system(size: 13))
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .padding(.vertical, 2)
        .tag(ShelfSelection.builtin(item))
    }
}
