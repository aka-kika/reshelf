import SwiftUI
import SwiftData
import AppKit

struct ProjectListView: View {
    @Binding var listSelection: CatalogListSelection?
    @Binding var searchText: String
    @Binding var sidebarSelection: ShelfSelection?
    @Binding var showingAddSheet: Bool
    /// With the sidebar collapsed, this column is at the window's top-left where
    /// the traffic lights sit — inset the header so they don't cover the buttons.
    var needsTrafficLightInset: Bool = false
    var onQuickCapture: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]
    @Query(sort: \CatalogFolder.sortIndex) private var folders: [CatalogFolder]

    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    /// Transient one-line status under the list header — clone progress, shelf
    /// moves, failures. (Was `compareNotice`; Compare merely introduced it.)
    @State private var statusNotice: String?
    @State private var pendingDeleteProject: ToolProject?
    /// Non-nil while the New Folder prompt is up; holds what goes into it.
    @State private var newFolderTargets: [ToolProject]?
    @State private var newFolderName = ""
    /// Rows checked for a batch action. Separate from `listSelection`, which is
    /// "what the inspector is showing" — a single project, always. Keeping them
    /// separate means ⌘-clicking a second row doesn't blank the inspector.
    @State private var batchSelection: Set<UUID> = []
    /// Anchor for ⇧-click range selection: the last row clicked without ⇧.
    @State private var batchAnchor: UUID?
    @State private var pendingBatchRemoveClones: [ToolProject]?
    @State private var pendingBatchDelete: [ToolProject]?
    @State private var pendingRemoveCloneProject: ToolProject?
    @State private var cloningProjectIDs: Set<UUID> = []
    @State private var behindProjectIDs: Set<UUID> = []
    @State private var isCheckingCloneUpdates = false
    @State private var isPullingClones = false
    /// Number of duplicate entries pending removal (drives the confirm dialog); nil = no dialog.
    @State private var pendingDuplicateRemoval: Int?
    @AppStorage("reshelf.catalogSortOrder") private var sortOrderRaw = CatalogSortOrder.recentlyAdded.rawValue

    private var sortOrder: CatalogSortOrder {
        CatalogSortOrder(rawValue: sortOrderRaw) ?? .recentlyAdded
    }

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader(
                leadingInset: needsTrafficLightInset ? ShelfLayout.trafficLightHeaderInset : 0
            ) {
                HStack(spacing: 8) {
                    HeaderChromeButton(systemImage: "sidebar.left", help: "Toggle Sidebar") {
                        NotificationCenter.default.post(name: .toggleSidebarColumn, object: nil)
                    }
                    Text(listTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    sortMenu
                    HeaderChromeButton(systemImage: "magnifyingglass", help: "Search (⌘K)") {
                        NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                    }
                    HeaderChromeButton(systemImage: "sidebar.right", help: "Toggle Inspector (⌘I)") {
                        NotificationCenter.default.post(name: .toggleInspectorColumn, object: nil)
                    }
                    if !searchText.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                            Text(searchText)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .titlebarClickable { searchText = "" }
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                }
            }

            if let statusNotice {
                HStack {
                    Text(statusNotice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { self.statusNotice = nil }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
            }

            Group {
                if filteredProjects.isEmpty {
                    catalogListEmptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredProjects) { project in
                                ProjectRowView(
                                    project: project,
                                    isSelected: listSelection?.projectID == project.id
                                        || batchSelection.contains(project.id),
                                    statusKey: project.statusRaw,
                                    isCloning: cloningProjectIDs.contains(project.id),
                                    isClonedLocally: CatalogCloneService.isCloned(project),
                                    isBehind: behindProjectIDs.contains(project.id),
                                    onSelect: { selectProject(project, modifiers: $0) }
                                )
                                .equatable()
                                .contextMenu {
                                    catalogContextMenu(for: project)
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                }
            }

            Divider()
            HStack {
                Text(listFooterSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !batchProjects.isEmpty {
                    Text("\(batchProjects.count) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Menu("Actions") {
                        batchActionMenu(for: batchProjects)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button("Clear") { clearBatchSelection() }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            IconFetcher.fetchAll(for: allProjects, in: modelContext)
        }
        .onChange(of: allProjects.count) { _, _ in
            IconFetcher.fetchAll(for: allProjects, in: modelContext)
        }
        .onChange(of: searchText) { _, _ in
            clearBatchSelection()
        }
        .onChange(of: sidebarSelection) { _, _ in
            clearBatchSelection()
        }
        .onChange(of: appRefreshStore.catalogRevision) { _, _ in
        }
        .modifier(CatalogEventHandlers(
            onCheckCloneUpdates: { checkAllClonesForUpdates() },
            onPullCloneUpdates: { pullFlaggedClones() },
            onMoveSelectedToShelf: { note in moveSelectedToShelf(note.object as? String) },
            onCloneStatusKnown: { note in syncBehindBadge(note) },
            onRemoveDuplicates: { requestRemoveDuplicates() }
        ))
        .confirmationDialog(
            "Remove \(pendingBatchRemoveClones?.count ?? 0) local clones?",
            isPresented: Binding(
                get: { pendingBatchRemoveClones != nil },
                set: { if !$0 { pendingBatchRemoveClones = nil } }
            ),
            presenting: pendingBatchRemoveClones
        ) { targets in
            Button("Move \(targets.count) Clones to Trash", role: .destructive) {
                for project in targets { removeClone(for: project) }
                statusNotice = "Moved \(targets.count) clones to the Trash."
                clearBatchSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: { targets in
            Text("\(targets.count) cloned folders move to the Trash — recoverable from there. The projects stay in your catalog and can be cloned again anytime.")
        }
        .confirmationDialog(
            "Remove \(pendingBatchDelete?.count ?? 0) projects from the catalog?",
            isPresented: Binding(
                get: { pendingBatchDelete != nil },
                set: { if !$0 { pendingBatchDelete = nil } }
            ),
            presenting: pendingBatchDelete
        ) { targets in
            Button("Remove \(targets.count) from Catalog", role: .destructive) {
                for project in targets { deleteProject(project) }
                statusNotice = "Removed \(targets.count) projects from the catalog."
                clearBatchSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: { targets in
            Text("This removes \(targets.count) entries from your shelf. A backup is written first, so Restore from Backup can bring them back. Cloned files on disk are left untouched.")
        }
        .alert("New Folder", isPresented: Binding(
            get: { newFolderTargets != nil },
            set: { if !$0 { newFolderTargets = nil } }
        )) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                if let targets = newFolderTargets,
                   let folder = CatalogFolderService.create(name: newFolderName, in: modelContext) {
                    assign(targets, to: folder)
                }
                newFolderTargets = nil
            }
            Button("Cancel", role: .cancel) { newFolderTargets = nil }
        } message: {
            Text("Group projects by what you got them for — a folder is a label, not a place on disk.")
        }
        .confirmationDialog(
            "Remove \(pendingDeleteProject?.name ?? "this project")?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { if !$0 { pendingDeleteProject = nil } }
            ),
            presenting: pendingDeleteProject
        ) { project in
            Button("Remove from Catalog", role: .destructive) {
                deleteProject(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("“\(project.name)” will be removed from your catalog. This can’t be undone. Cloned files and intelligence data are left untouched.")
        }
        .confirmationDialog(
            "Remove the local clone of \(pendingRemoveCloneProject?.name ?? "this repo")?",
            isPresented: Binding(
                get: { pendingRemoveCloneProject != nil },
                set: { if !$0 { pendingRemoveCloneProject = nil } }
            ),
            presenting: pendingRemoveCloneProject
        ) { project in
            Button("Move Clone to Trash", role: .destructive) {
                removeClone(for: project)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("The cloned folder is moved to the Trash — you can recover it from there. “\(project.name)” stays in your catalog and can be cloned again anytime.")
        }
        .confirmationDialog(
            "Remove duplicate repos?",
            isPresented: Binding(
                get: { pendingDuplicateRemoval != nil },
                set: { if !$0 { pendingDuplicateRemoval = nil } }
            ),
            presenting: pendingDuplicateRemoval
        ) { count in
            Button("Remove \(count) Duplicate\(count == 1 ? "" : "s")", role: .destructive) {
                performRemoveDuplicates()
            }
            Button("Cancel", role: .cancel) {}
        } message: { count in
            Text("\(count) duplicate entr\(count == 1 ? "y" : "ies") will be removed, keeping the best-filled copy of each repo. A backup is saved first, and cloned files are left untouched.")
        }
    }

    private var listFooterSummary: String {
        let projectCount = filteredProjects.count
        return "\(projectCount) project\(projectCount == 1 ? "" : "s")"
    }

    /// A plain click selects one project and drops any batch selection. ⌘-click
    /// toggles a row into the batch; ⇧-click extends from the last plain click.
    /// The inspector keeps following `listSelection` throughout, so building a
    /// batch never costs you the detail view of what you last looked at.
    private func selectProject(_ project: ToolProject, modifiers: EventModifiers = []) {
        if modifiers.contains(.command) {
            if batchSelection.contains(project.id) {
                batchSelection.remove(project.id)
            } else {
                batchSelection.insert(project.id)
                if batchAnchor == nil { batchAnchor = project.id }
            }
            return
        }
        if modifiers.contains(.shift), let anchor = batchAnchor ?? listSelection?.projectID {
            let ids = filteredProjects.map(\.id)
            if let from = ids.firstIndex(of: anchor), let to = ids.firstIndex(of: project.id) {
                batchSelection.formUnion(ids[min(from, to)...max(from, to)])
                return
            }
        }
        batchSelection.removeAll()
        batchAnchor = project.id
        listSelection = .project(project.id)
    }

    /// The batch, in the list's order — so "move 12 to Yard Sale" reports and acts
    /// in the order the user sees, and rows filtered out of view are excluded.
    private var batchProjects: [ToolProject] {
        filteredProjects.filter { batchSelection.contains($0.id) }
    }

    private func clearBatchSelection() {
        batchSelection.removeAll()
        batchAnchor = nil
    }

    /// The batch actions, shared by the footer menu and the row context menu so
    /// there is one definition of what a batch can do.
    @ViewBuilder
    private func batchActionMenu(for projects: [ToolProject]) -> some View {
        Menu("Move \(projects.count) to") {
            ForEach(ProjectStatus.allCases, id: \.self) { shelf in
                Button {
                    for project in projects where project.status != shelf {
                        project.status = shelf
                    }
                    try? modelContext.save()
                    statusNotice = "Moved \(projects.count) project\(projects.count == 1 ? "" : "s") to \(shelf.displayName)."
                    clearBatchSelection()
                } label: {
                    Label(shelf.displayName, systemImage: shelf.sfSymbol)
                }
            }
        }

        folderMenu(for: projects)

        let cloned = projects.filter { CatalogCloneService.isCloned($0) }
        if !cloned.isEmpty {
            Divider()
            Button("Remove \(cloned.count) Local Clone\(cloned.count == 1 ? "" : "s")…", role: .destructive) {
                pendingBatchRemoveClones = cloned
            }
        }

        Divider()
        Button("Remove \(projects.count) from Catalog…", role: .destructive) {
            pendingBatchDelete = projects
        }
    }

 
 
    @ViewBuilder
    private func catalogContextMenu(for project: ToolProject) -> some View {
        // Right-clicking inside a batch acts on the batch; right-clicking outside
        // one acts on that row alone. Anything else would silently apply a
        // destructive action to rows the user wasn't pointing at.
        if batchSelection.contains(project.id), batchSelection.count > 1 {
            batchActionMenu(for: batchProjects)
        } else {
            singleProjectContextMenu(for: project)
        }
    }

    @ViewBuilder
    private func singleProjectContextMenu(for project: ToolProject) -> some View {
        // Link actions (open / copy) live on the links in the inspector, not here.
        // — Shelf — one-tap triage between shelves
        Menu("Move to") {
            ForEach(ProjectStatus.allCases.filter { $0 != project.status }, id: \.self) { shelf in
                Button {
                    setShelf(shelf, for: project)
                } label: {
                    Label(shelf.displayName, systemImage: shelf.sfSymbol)
                }
            }
        }

        // — Folders — a user-made grouping ("everything I cloned for X"),
        // orthogonal to both the shelf above and the fixed category taxonomy.
        folderMenu(for: [project])

        // — Local copy — clone the repo to disk (no AI / intelligence needed)
        if !project.githubURL.trimmingCharacters(in: .whitespaces).isEmpty {
            Divider()
            if CatalogCloneService.isCloned(project),
               let dest = CatalogCloneService.destination(for: project) {
                Button("Reveal Clone in Finder") {
                    CatalogCloneService.revealInFinder(dest)
                }
                Button("Remove Local Clone…", role: .destructive) {
                    pendingRemoveCloneProject = project
                }
            } else if cloningProjectIDs.contains(project.id) {
                Button("Cloning…") {}.disabled(true)
            } else {
                Button("Clone Repository") { cloneProject(project) }
            }
        }

        Divider()

        // — Catalog —
        Button("Remove from Catalog…", role: .destructive) {
            pendingDeleteProject = project
        }
    }

    /// Takes an array rather than one project so the same menu serves a single
    /// row and a multi-row selection.
    @ViewBuilder
    private func folderMenu(for projects: [ToolProject]) -> some View {
        Menu(projects.count == 1 ? "Add to Folder" : "Add \(projects.count) to Folder") {
            ForEach(folders) { folder in
                Button {
                    assign(projects, to: folder)
                } label: {
                    // A checkmark when every project named is already in it,
                    // so the menu reads correctly for a mixed selection too.
                    if projects.allSatisfy({ $0.folderID == folder.id }) {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            if !folders.isEmpty { Divider() }
            Button("New Folder…") {
                newFolderTargets = projects
                newFolderName = ""
            }
            if projects.contains(where: { $0.folderID != nil }) {
                Divider()
                Button("Remove from Folder") {
                    assign(projects, to: nil)
                }
            }
        }
    }

    private func assign(_ projects: [ToolProject], to folder: CatalogFolder?) {
        CatalogFolderService.assign(projects, to: folder, in: modelContext)
        let what = projects.count == 1 ? projects[0].name : "\(projects.count) projects"
        statusNotice = folder == nil
            ? "Removed \(what) from its folder."
            : "Added \(what) to \(folder!.name)."
    }

    private func setShelf(_ shelf: ProjectStatus, for project: ToolProject) {
        project.status = shelf
        try? modelContext.save()
    }

 
 
    /// ⌘T / ⌘Y / ⌘⇧G — move the currently selected repo to a shelf.
    private func moveSelectedToShelf(_ rawStatus: String?) {
        guard let rawStatus, let shelf = ProjectStatus(rawValue: rawStatus),
              let id = listSelection?.projectID,
              let project = allProjects.first(where: { $0.id == id }) else { return }
        guard project.status != shelf else { return }
        setShelf(shelf, for: project)
        statusNotice = "Moved \(project.name) to \(shelf.displayName)."
    }

    private func cloneProject(_ project: ToolProject) {
        cloningProjectIDs.insert(project.id)
        statusNotice = "Cloning \(project.name)…"
        Task {
            do {
                let dest = try await CatalogCloneService.clone(project)
                await MainActor.run {
                    cloningProjectIDs.remove(project.id)
                    statusNotice = "Cloned \(project.name) to \(dest.path)."
                }
            } catch {
                await MainActor.run {
                    cloningProjectIDs.remove(project.id)
                    statusNotice = "Clone failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func removeClone(for project: ToolProject) {
        do {
            try CatalogCloneService.removeClone(project)
            behindProjectIDs.remove(project.id)
            statusNotice = "Moved the \(project.name) clone to the Trash."
        } catch {
            statusNotice = "Couldn't remove clone: \(error.localizedDescription)"
        }
    }

    /// Checks every cloned repo against its upstream (cheap `ls-remote`, no fetch)
    /// and flags the ones that are behind with a dot on their row. On-demand only.
    private func checkAllClonesForUpdates() {
        guard !isCheckingCloneUpdates else { return }
        let cloned = allProjects.filter { CatalogCloneService.isCloned($0) }
        guard !cloned.isEmpty else {
            statusNotice = "No cloned repositories to check."
            return
        }
        isCheckingCloneUpdates = true
        statusNotice = "Checking \(cloned.count) clone\(cloned.count == 1 ? "" : "s") for updates…"
        Task {
            var behind: Set<UUID> = []
            for project in cloned {
                if case .updatesAvailable = await CatalogCloneService.updateStatus(for: project) {
                    behind.insert(project.id)
                }
            }
            await MainActor.run {
                behindProjectIDs = behind
                isCheckingCloneUpdates = false
                if behind.isEmpty {
                    statusNotice = "All clones are up to date."
                } else {
                    statusNotice = "\(behind.count) clone\(behind.count == 1 ? " has" : "s have") updates available. Press ⌘U to pull all."
                }
            }
        }
    }

    /// Pulls only the clones currently flagged behind (by a prior ⌘⇧U check) — ⌘U.
    /// Each is synced to upstream; its row dot clears on success. Clones with local
    /// edits are skipped and reported, never clobbered.
    private func pullFlaggedClones() {
        guard !isPullingClones else { return }
        let flagged = allProjects.filter { behindProjectIDs.contains($0.id) }
        guard !flagged.isEmpty else {
            statusNotice = "No clones flagged — run Check Clones for Updates (⌘⇧U) first."
            return
        }
        isPullingClones = true
        statusNotice = "Pulling \(flagged.count) clone\(flagged.count == 1 ? "" : "s")…"
        Task {
            var updated = 0
            var skipped = 0
            var failed: [String] = []
            var pulledIDs: Set<UUID> = []
            for project in flagged {
                do {
                    try await CatalogCloneService.pull(project)
                    updated += 1
                    pulledIDs.insert(project.id)
                } catch let error as GitClientError {
                    if case .localChangesPresent = error { skipped += 1 } else { failed.append(project.name) }
                } catch {
                    failed.append(project.name)
                }
            }
            await MainActor.run {
                behindProjectIDs.subtract(pulledIDs)
                isPullingClones = false
                statusNotice = pullSummary(updated: updated, skipped: skipped, failed: failed)
            }
        }
    }

    /// One-line result for a Pull All run, e.g.
    /// "Updated 2 · 1 skipped (local changes) · 1 failed (zotero)".
    private func pullSummary(updated: Int, skipped: Int, failed: [String]) -> String {
        var parts: [String] = []
        if updated > 0 { parts.append("Updated \(updated)") }
        if skipped > 0 { parts.append("\(skipped) skipped (local changes)") }
        if !failed.isEmpty {
            let names = failed.prefix(3).joined(separator: ", ")
            let overflow = failed.count > 3 ? " +\(failed.count - 3)" : ""
            parts.append("\(failed.count) failed (\(names)\(overflow))")
        }
        return parts.isEmpty ? "Nothing to pull." : parts.joined(separator: " · ") + "."
    }

    /// Keep a row's "updates available" dot in sync with what the inspector found
    /// (e.g. clear it right after a pull, or set it when a check finds it behind).
    private func syncBehindBadge(_ note: Notification) {
        guard let idStr = note.object as? String, let id = UUID(uuidString: idStr) else { return }
        let behind = (note.userInfo?["behind"] as? Bool) ?? false
        if behind {
            behindProjectIDs.insert(id)
        } else {
            behindProjectIDs.remove(id)
        }
    }

    // MARK: - De-duplicate

    /// Groups of catalog entries that are the same repo (by normalized owner/repo).
    private func duplicateGroups() -> [[ToolProject]] {
        var groups: [String: [ToolProject]] = [:]
        for project in allProjects {
            guard IconFetcher.extractOwnerRepo(from: project.githubURL) != nil else { continue }
            let key = IconFetcher.repoDedupKey(for: project.githubURL)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(project)
        }
        return groups.values.filter { $0.count > 1 }
    }

    /// Higher = keep. Prefers a higher shelf, then richer/edited data, then the
    /// original (earliest added) — so the copy you invested in survives.
    private func dedupKeepScore(_ p: ToolProject) -> Int {
        var score = 0
        switch p.status {
        case .topShelf: score += 3000
        case .collector: score += 2000
        case .yardSale: score += 1000
        }
        if !p.notes.isEmpty { score += 50 }
        score += min(p.tags.count, 20)
        score += min(p.useCases.count, 20) * 2
        if !p.longDescription.isEmpty { score += 20 }
        if !p.websiteURL.isEmpty { score += 10 }
        if !p.license.isEmpty { score += 5 }
        if p.fitScore != 3 { score += 10 }
        if p.lastCheckedDate != nil { score += 10 }
        return score
    }

    private func requestRemoveDuplicates() {
        let victims = duplicateGroups().reduce(0) { $0 + ($1.count - 1) }
        if victims == 0 {
            statusNotice = "No duplicate repos found."
        } else {
            pendingDuplicateRemoval = victims
        }
    }

    private func performRemoveDuplicates() {
        let groups = duplicateGroups()
        guard !groups.isEmpty else { return }
        CatalogBackupService.writeSnapshot(allProjects, folders: folders) // recoverable via Restore from Backup
        var removed = 0
        for group in groups {
            let ranked = group.sorted { a, b in
                let sa = dedupKeepScore(a), sb = dedupKeepScore(b)
                return sa == sb ? a.addedDate < b.addedDate : sa > sb
            }
            for victim in ranked.dropFirst() {
                if listSelection?.projectID == victim.id { listSelection = nil }
                modelContext.delete(victim)
                removed += 1
            }
        }
        try? modelContext.save()
        statusNotice = "Removed \(removed) duplicate\(removed == 1 ? "" : "s"). A backup was saved."
    }

    // MARK: - Context-menu action helpers

    /// The on-disk clone worktree for a project, if intelligence has cloned it.
    /// Reads the tracked `localPath` from the intelligence record so it stays
    /// correct even if the user later changes the clone-root setting.
    private func cloneWorktreeURL(for project: ToolProject) -> URL? {
        guard let record = IntelligenceRepositoryBridge.findIntelligenceRepository(for: project),
              let path = record.localPath,
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func deleteProject(_ project: ToolProject) {
        if listSelection?.projectID == project.id {
            listSelection = nil
        }
        let name = project.name
        modelContext.delete(project)
        try? modelContext.save()
        AppRefreshBus.emit(.catalogStateUpdated)
        statusNotice = "Removed “\(name)” from the catalog."
    }

 
 
 
 
 
 
 
 

    private var filteredProjects: [ToolProject] {
        let bySidebar = applySidebarFilter(allProjects)
        let bySearch = searchText.isEmpty
            ? bySidebar
            : bySidebar.filter { $0.matchesSearch(searchText) }
        return sortOrder.sorted(bySearch)
    }

    /// Header control to pick how the list is ordered (Recently Added / Name / Stars).
    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrderRaw) {
                ForEach(CatalogSortOrder.allCases) { order in
                    Label(order.displayName, systemImage: order.icon).tag(order.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort: \(sortOrder.displayName)")
        .titlebarClickable()
    }

    /// What the list is showing. A folder selection names the folder; a folder
    /// that has since been deleted falls back rather than showing a stale name.
    private var listTitle: String {
        if let item = sidebarSelection?.builtinItem { return item.title }
        if let id = sidebarSelection?.folderID,
           let folder = folders.first(where: { $0.id == id }) {
            return folder.name
        }
        return "All Projects"
    }

    private func applySidebarFilter(_ projects: [ToolProject]) -> [ToolProject] {
        if let id = sidebarSelection?.folderID {
            return projects.filter { $0.folderID == id }
        }
        guard let item = sidebarSelection?.builtinItem, item.isCatalogFilter else { return projects }
        return projects.filter { item.matchesCatalogFilter($0) }
    }

    private var catalogListEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: catalogEmptyStateIcon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.35))
            Text(catalogEmptyStateTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(catalogEmptyStateMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            if catalogEmptyStateShowsCaptureActions {
                HStack(spacing: 8) {
                    Button("Quick Capture") { onQuickCapture() }
                        .controlSize(.small)
                    Button("Add Project") { showingAddSheet = true }
                        .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var catalogEmptyStateIcon: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "magnifyingglass" }
        if sidebarSelection != nil, sidebarSelection?.builtinItem?.isCatalogFilter != false {
            return "line.3.horizontal.decrease.circle"
        }
        return "tray"
    }

    private var catalogEmptyStateTitle: String {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty { return "No search results" }
        if let item = sidebarSelection?.builtinItem, item.isCatalogFilter {
            return "No projects in \(item.title)"
        }
        if sidebarSelection?.folderID != nil {
            return "This folder is empty"
        }
        return "Your shelf is empty"
    }

    private var catalogEmptyStateMessage: String {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty {
            return "Nothing matched \"\(trimmedSearch)\". Try a different name, tag, or paste a GitHub URL."
        }
        if sidebarSelection?.builtinItem?.isCatalogFilter == true {
            return "No projects match this filter yet. Capture more repos, or pick another sidebar filter."
        }
        if sidebarSelection?.folderID != nil {
            return "Nothing is in this folder yet. Right-click a project and pick Add to Folder."
        }
        return "Capture a GitHub repo to start building your personal open-source shelf."
    }

    private var catalogEmptyStateShowsCaptureActions: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            && sidebarSelection?.builtinItem?.isCatalogFilter != true
            && sidebarSelection?.folderID == nil
            && allProjects.isEmpty
    }
}

struct ProjectRowView: View, Equatable {
    let project: ToolProject
    var isSelected: Bool = false
    /// Captured status value so `.equatable()` detects a shelf move (status changes
    /// but the project reference stays the same, so we can't read it live in `==`).
    var statusKey: String = ""
    var isCloning: Bool = false
    var isClonedLocally: Bool = false
    /// Local clone is behind its upstream (updates available to pull).
    var isBehind: Bool = false
    /// Carries the modifier keys held at click time so the list can tell a
    /// plain click from ⌘-click (toggle into batch) and ⇧-click (extend).
    var onSelect: ((EventModifiers) -> Void)?

    @Environment(\.modelContext) private var modelContext

    static func == (lhs: ProjectRowView, rhs: ProjectRowView) -> Bool {
        lhs.project.id == rhs.project.id
            && lhs.statusKey == rhs.statusKey
            && lhs.isCloning == rhs.isCloning
            && lhs.isClonedLocally == rhs.isClonedLocally
            && lhs.isBehind == rhs.isBehind
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(spacing: 10) {
            ProjectIcon(project: project)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(project.shortDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !project.category.isEmpty {
                        Text(project.category)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if !project.category.isEmpty && project.status != .collector {
                        Text("·")
                            .foregroundStyle(.secondary)
                    }
                    if project.status != .collector {
                        StatusBadge(status: project.status)
                    }
                }
            }

            Spacer(minLength: 8)

            if isCloning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .help("Cloning…")
            } else if isClonedLocally {
                Image(systemName: "internaldrive")
                    .font(.system(size: 12))
                    .foregroundStyle(isBehind ? Color.orange : .secondary)
                    .overlay(alignment: .topTrailing) {
                        if isBehind {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 5, height: 5)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .help(isBehind ? "Updates available — pull to update" : "Cloned to disk")
            }

        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .onTapGesture {
            // SwiftUI's tap gesture doesn't carry modifiers on macOS; read them
            // from the event that is still current when the handler runs.
            var modifiers: EventModifiers = []
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            onSelect?(modifiers)
        }
    }
}

private func isGitHubURL(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("https://github.com/") || trimmed.hasPrefix("github.com/")
}

/// Bundles the catalog's notification `.onReceive` handlers into one modifier so
/// the main `body` modifier chain stays short enough for the type-checker.
private struct CatalogEventHandlers: ViewModifier {
    let onCheckCloneUpdates: () -> Void
    let onPullCloneUpdates: () -> Void
    let onMoveSelectedToShelf: (Notification) -> Void
    let onCloneStatusKnown: (Notification) -> Void
    let onRemoveDuplicates: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .checkCloneUpdates)) { _ in onCheckCloneUpdates() }
            .onReceive(NotificationCenter.default.publisher(for: .pullCloneUpdates)) { _ in onPullCloneUpdates() }
            .onReceive(NotificationCenter.default.publisher(for: .moveSelectedToShelf), perform: onMoveSelectedToShelf)
            .onReceive(NotificationCenter.default.publisher(for: .cloneUpdateStatusKnown), perform: onCloneStatusKnown)
            .onReceive(NotificationCenter.default.publisher(for: .removeDuplicateRepos)) { _ in onRemoveDuplicates() }
    }
}

/// How the catalog list is ordered. Persisted via `@AppStorage`.
enum CatalogSortOrder: String, CaseIterable, Identifiable {
    case recentlyAdded
    case lastUpdated
    case name
    case stars

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .lastUpdated: "Recently Updated"
        case .name: "Name (A–Z)"
        case .stars: "Most Stars"
        }
    }

    var icon: String {
        switch self {
        case .recentlyAdded: "clock"
        case .lastUpdated: "arrow.trianglehead.2.clockwise"
        case .name: "textformat"
        case .stars: "star"
        }
    }

    func sorted(_ projects: [ToolProject]) -> [ToolProject] {
        switch self {
        case .recentlyAdded:
            return projects.sorted { $0.addedDate > $1.addedDate }
        case .lastUpdated:
            // Newest upstream activity first. Rows with no date yet (never
            // captured with it, never refreshed) sink to the bottom rather than
            // pretending to be ancient, and tie-break by name so the order is stable.
            return projects.sorted {
                switch ($0.lastUpdatedDate, $1.lastUpdatedDate) {
                case let (l?, r?):
                    return l == r
                        ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        : l > r
                case (nil, nil):
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                }
            }
        case .name:
            return projects.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .stars:
            return projects.sorted {
                let a = Self.starValue($0.stars), b = Self.starValue($1.stars)
                // Ties (and blanks) fall back to name so order stays stable.
                return a == b
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : a > b
            }
        }
    }

    /// Parse a GitHub-style star string ("18.2k", "1.5M", "342", "1,024") into a
    /// number for sorting. Blank/unparseable values sort last (-1).
    static func starValue(_ raw: String) -> Double {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return -1 }
        var multiplier = 1.0
        if s.hasSuffix("k") { multiplier = 1_000; s.removeLast() }
        else if s.hasSuffix("m") { multiplier = 1_000_000; s.removeLast() }
        s = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(s) else { return -1 }
        return value * multiplier
    }
}
