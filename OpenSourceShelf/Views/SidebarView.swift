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
    /// Collapsed/expanded per section, remembered across launches.
    @AppStorage("reshelf.sidebar.foldersExpanded") private var foldersExpanded = true
    @AppStorage("reshelf.sidebar.categoriesExpanded") private var categoriesExpanded = true
    @AppStorage("reshelf.sidebar.tagsExpanded") private var tagsExpanded = true
    /// Set in Settings → General → Sidebar Tags.
    @AppStorage(SidebarTagRanking.modeKey) private var tagsMode: SidebarTagRanking.Mode = .top

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
        var tags = SidebarTagRanking.tags(in: allProjects, mode: tagsMode)
        // A tag picked from the inspector may sit outside the top list; keep its
        // row visible so the selection has somewhere to show.
        if let key = selection?.tagName, !tags.contains(where: { $0.key == key }),
           let picked = SidebarTagRanking.tag(forKey: key, in: allProjects) {
            tags.append(picked)
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
                    // Collapsible: hover the heading for the native chevron, or
                    // click the heading itself.
                    Section(isExpanded: $foldersExpanded) {
                        ForEach(folders) { folder in
                            FolderSidebarRow(
                                folder: folder,
                                count: memberCount(of: folder)
                            )
                            .contextMenu {
                                Button("Pull Repos") {
                                    NotificationCenter.default.post(name: .pullFolderClones, object: folder.id)
                                }
                                .disabled(!hasClones(in: folder))
                                Divider()
                                Button("Rename…") { renameTarget = folder }
                                Button("Delete Folder…") { deleteTarget = folder }
                            }
                        }
                    } header: {
                        collapsibleHeader(.folders, isExpanded: $foldersExpanded)
                    }
                }

                if !categories.isEmpty {
                    Section(isExpanded: $categoriesExpanded) {
                        ForEach(categories) { item in
                            SidebarRow(item: item, count: counts.count(for: item))
                        }
                    } header: {
                        collapsibleHeader(.categories, isExpanded: $categoriesExpanded)
                    }
                }

                if !tags.isEmpty {
                    Section(isExpanded: $tagsExpanded) {
                        ForEach(tags, id: \.key) { tag in
                            TagSidebarRow(key: tag.key, name: tag.name, count: tag.count)
                        }
                    } header: {
                        collapsibleHeader(.tags, isExpanded: $tagsExpanded)
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
            .onChange(of: selection) { _, new in
                if new?.tagName != nil { tagsExpanded = true }
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

    /// Section heading that toggles its section on click — the native hover
    /// chevron alone is easy to miss.
    private func collapsibleHeader(_ section: SidebarSection, isExpanded: Binding<Bool>) -> some View {
        Text(section.rawValue)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
            }
            .help(isExpanded.wrappedValue ? "Hide \(section.rawValue)" : "Show \(section.rawValue)")
    }

    /// Counted from the already-loaded `@Query` rather than a fetch, so a row
    /// updates the moment a project's folder changes.
    private func memberCount(of folder: CatalogFolder) -> Int {
        allProjects.filter { $0.folderID == folder.id }.count
    }

    /// Only offer Pull when there's a clone to pull (the clone lookup is a
    /// cached index, so this stays cheap per row).
    private func hasClones(in folder: CatalogFolder) -> Bool {
        allProjects.contains { $0.folderID == folder.id && CatalogCloneService.isCloned($0) }
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

/// A tag row: filters the list to repos carrying that GitHub topic.
private struct TagSidebarRow: View {
    let key: String
    let name: String
    let count: Int

    var body: some View {
        HStack {
            Image(systemName: "number")
                .frame(width: 20)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
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
        .padding(.vertical, 2)
        .tag(ShelfSelection.tag(key))
    }
}

/// Which GitHub topics the sidebar's Tags section offers. Tags cut across
/// categories — "swift" finds every Swift repo whatever its category — so
/// only pure noise ("open-source", "awesome") is skipped.
enum SidebarTagRanking {
    static let modeKey = "reshelf.sidebar.tagsMode"

    enum Mode: String {
        case top, recent
    }

    static let limit = 15
    /// How many of the newest repos "Recent" looks at.
    static let recentWindow = 40

    /// "menu-bar" and "menubar" are the same tag: grouped under one key.
    static func key(for tag: String) -> String {
        String(tag.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func tags(in projects: [ToolProject], mode: Mode) -> [(key: String, name: String, count: Int)] {
        // Counts always cover the whole shelf, so a row's number matches what
        // clicking it shows. Mode only changes *which* tags are listed.
        var totals: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for project in projects {
            var seen = Set<String>()
            for raw in project.tags {
                let tag = raw.lowercased()
                guard isUseful(tag) else { continue }
                let k = key(for: tag)
                spellings[k, default: [:]][tag, default: 0] += 1
                if seen.insert(k).inserted { totals[k, default: 0] += 1 }
            }
        }
        let names: [String]
        switch mode {
        case .top:
            names = totals.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        case .recent:
            // Rank by how often a tag shows up among the newest repos; the
            // shelf-wide total breaks ties.
            var recent: [String: Int] = [:]
            for project in projects.sorted(by: { $0.addedDate > $1.addedDate }).prefix(recentWindow) {
                for tag in Set(project.tags.map { key(for: $0) }) where totals[tag] != nil {
                    recent[tag, default: 0] += 1
                }
            }
            names = recent.keys.sorted {
                (recent[$0]!, totals[$0]!, $1) > (recent[$1]!, totals[$1]!, $0)
            }
        }
        // Show the spelling used most ("menu-bar" over "menubar").
        return names.prefix(limit).map { k in
            let name = spellings[k]?.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? k
            return (k, name, totals[k] ?? 0)
        }
    }

    /// One tag's row data by key, whether or not it made the ranked list.
    static func tag(forKey key: String, in projects: [ToolProject]) -> (key: String, name: String, count: Int)? {
        var spellings: [String: Int] = [:]
        var count = 0
        for project in projects {
            let matches = project.tags.filter { self.key(for: $0) == key }
            guard !matches.isEmpty else { continue }
            count += 1
            for tag in matches { spellings[tag.lowercased(), default: 0] += 1 }
        }
        guard count > 0 else { return nil }
        let name = spellings.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? key
        return (key, name, count)
    }

    private static let redundant: Set<String> = {
        Set(["open-source", "hacktoberfest", "awesome", "awesome-list"].map(key(for:)))
    }()

    static func isUseful(_ tag: String) -> Bool {
        !tag.isEmpty && !redundant.contains(key(for: tag))
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
