import SwiftUI
import SwiftData
import AppKit

struct ProjectListView: View {
    @Binding var listSelection: CatalogListSelection?
    @Binding var searchText: String
    @Binding var sidebarSelection: SidebarItem?
    @Binding var showingAddSheet: Bool
    /// With the sidebar collapsed, this column is at the window's top-left where
    /// the traffic lights sit — inset the header so they don't cover the buttons.
    var needsTrafficLightInset: Bool = false
    var onQuickCapture: () -> Void
    var onCompareRepositoryIDs: ([String]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]

    @EnvironmentObject private var catalogStateStore: CatalogIntelligenceStateStore
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @AppStorage(LabsFeatures.storageKey) private var labsFeaturesEnabled = false
    @State private var isCompareSelectMode = false
    @State private var compareSelectedProjectIDs: Set<UUID> = []
    @State private var compareNotice: String?
    @State private var isBatchFetchingIntelligence = false
    @State private var isBatchRunbookActionRunning = false
    @State private var runbookFilter: CatalogRunbookFilter = .all
    @State private var pendingDeleteProject: ToolProject?
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
                    Text(sidebarSelection?.title ?? "All Projects")
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

            if let compareNotice {
                HStack {
                    Text(compareNotice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { self.compareNotice = nil }
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
                                    catalogState: catalogStateStore.state(for: project),
                                    isCompareSelectMode: isCompareSelectMode,
                                    isCompareSelected: compareSelectedProjectIDs.contains(project.id),
                                    isSelected: listSelection?.projectID == project.id,
                                    showsIntelligence: labsFeaturesEnabled,
                                    statusKey: project.statusRaw,
                                    isCloning: cloningProjectIDs.contains(project.id),
                                    isClonedLocally: CatalogCloneService.isCloned(project),
                                    isBehind: behindProjectIDs.contains(project.id),
                                    onSelect: { selectProject(project) }
                                ) {
                                    toggleCompareSelection(for: project)
                                }
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
                if runbookFilter != .all {
                    Text("· \(runbookFilter.rawValue)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if isCompareSelectMode, !compareSelectedProjectIDs.isEmpty {
                    Text("· \(compareSelectedProjectIDs.count) selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            IconFetcher.fetchAll(for: allProjects, in: modelContext)
            catalogStateStore.refresh(projects: filteredProjects, includeFreshnessEvaluation: true)
        }
        .onChange(of: allProjects.count) { _, _ in
            IconFetcher.fetchAll(for: allProjects, in: modelContext)
            catalogStateStore.refresh(projects: filteredProjects, includeFreshnessEvaluation: true)
        }
        .onChange(of: searchText) { _, _ in
            catalogStateStore.refresh(projects: filteredProjects)
        }
        .onChange(of: sidebarSelection) { _, _ in
            catalogStateStore.refresh(projects: filteredProjects)
        }
        .onChange(of: runbookFilter) { _, _ in
            catalogStateStore.refresh(projects: filteredProjects)
        }
        .onChange(of: appRefreshStore.catalogRevision) { _, _ in
            catalogStateStore.refresh(projects: filteredProjects)
        }
        .modifier(CatalogEventHandlers(
            onCatalogQuickAction: { notification in
                guard let raw = notification.userInfo?["action"] as? String,
                      let action = AppQuickAction(rawValue: raw) else { return }
                handleCatalogQuickAction(action)
            },
            onSetRunbookFilter: { notification in
                guard let raw = notification.userInfo?["filter"] as? String,
                      let filter = CatalogRunbookFilter(rawValue: raw) else { return }
                runbookFilter = filter
            },
            onToggleCompareMode: { toggleCompareMode() },
            onFetchAllIntelligence: { fetchIntelligenceForAllVisible() },
            onCompareSelected: { compareSelectedProjects() },
            onCancelCompareMode: { cancelCompareMode() },
            onCheckCloneUpdates: { checkAllClonesForUpdates() },
            onPullCloneUpdates: { pullFlaggedClones() },
            onMoveSelectedToShelf: { note in moveSelectedToShelf(note.object as? String) },
            onCloneStatusKnown: { note in syncBehindBadge(note) },
            onRemoveDuplicates: { requestRemoveDuplicates() }
        ))
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

    private func selectProject(_ project: ToolProject) {
        listSelection = .project(project.id)
    }

    private func handleCatalogQuickAction(_ action: AppQuickAction) {
        switch action {
        case .showNeedsRunbook:
            runbookFilter = .needsRunbook
        case .showStaleRunbooks:
            runbookFilter = .staleRunbooks
        case .regenerateStaleRunbooks:
            batchRegenerateStaleRunbooksForVisible()
        case .refreshIntelligence:
            fetchIntelligenceForAllVisible()
        default:
            break
        }
    }

    private func batchRegenerateStaleRunbooksForVisible() {
        let targets = filteredProjects.filter {
            catalogStateStore.state(for: $0).runbookBadge == .staleRunbook
        }
        guard !targets.isEmpty else {
            compareNotice = "No stale runbooks in the current list."
            return
        }
        isBatchRunbookActionRunning = true
        let result = CatalogRunbookBatchService.regenerateStaleRunbooks(for: targets)
        CatalogRunbookBatchService.emitBatchGenerateEvent(for: result)
        isBatchRunbookActionRunning = false
        compareNotice = result.summaryMessage
        catalogStateStore.refresh(projects: filteredProjects)
    }

    @ViewBuilder
    private func catalogContextMenu(for project: ToolProject) -> some View {
        // Link actions (open / copy) live on the links in the inspector, not here.
        // — Intelligence (v2 — Labs only): clone, runbooks, compare —
        if labsFeaturesEnabled {
            let state = catalogStateStore.state(for: project)
            let snapshot = state.intelligenceSnapshot

            if snapshot.status.canFetch, IntelligenceRepositoryBridge.resolvedGitHubURL(for: project) != nil {
                Button(snapshot.status == .failed ? "Retry Intelligence Fetch" : "Fetch Intelligence (Clone & Analyze)") {
                    fetchIntelligence(for: project)
                }
            } else if snapshot.status.canFetch {
                Button("Fetch Intelligence") {}
                    .disabled(true)
            }

            if let cloneURL = cloneWorktreeURL(for: project) {
                Button("Reveal Clone in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([cloneURL])
                }
            }

            if let repositoryID = state.repositoryID, state.hasIntelligence {
                Button("Generate Runbook") {
                    enqueueRunbook(for: repositoryID, force: false)
                }
                if state.runbookBadge != .neverGenerated && state.runbookBadge != .noIntelligence {
                    Button("Open Runbook") {
                        RunbookDeepLinkNotifier.post(
                            RunbookDeepLinkRequest(repositoryID: repositoryID)
                        )
                    }
                }
            }

            if let repositoryID = state.repositoryID {
                if snapshot.status == .ready {
                    Button("Add to Compare") {
                        CompareDeepLinkNotifier.post(
                            CompareDeepLinkRequest(intent: .addRepository(repositoryID))
                        )
                        sidebarSelection = .compare
                    }
                } else {
                    Button("Add to Compare") {}
                        .disabled(true)
                }
            }

            if isCompareSelectMode {
                Button(compareSelectedProjectIDs.contains(project.id) ? "Deselect for Compare" : "Select for Compare") {
                    toggleCompareSelection(for: project)
                }
            }

            Divider()
        }

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

    private func setShelf(_ shelf: ProjectStatus, for project: ToolProject) {
        project.status = shelf
        try? modelContext.save()
        catalogStateStore.refresh(projects: filteredProjects)
    }

    private func toggleCompareMode() {
        if isCompareSelectMode {
            isCompareSelectMode = false
            compareSelectedProjectIDs = []
            compareNotice = nil
        } else {
            isCompareSelectMode = true
            compareNotice = "Select 2–4 projects, then use Catalog → Compare Selected."
        }
    }

    private func cancelCompareMode() {
        isCompareSelectMode = false
        compareSelectedProjectIDs = []
        compareNotice = nil
    }

    /// ⌘T / ⌘Y / ⌘⇧G — move the currently selected repo to a shelf.
    private func moveSelectedToShelf(_ rawStatus: String?) {
        guard let rawStatus, let shelf = ProjectStatus(rawValue: rawStatus),
              let id = listSelection?.projectID,
              let project = allProjects.first(where: { $0.id == id }) else { return }
        guard project.status != shelf else { return }
        setShelf(shelf, for: project)
        compareNotice = "Moved \(project.name) to \(shelf.displayName)."
    }

    private func cloneProject(_ project: ToolProject) {
        cloningProjectIDs.insert(project.id)
        compareNotice = "Cloning \(project.name)…"
        Task {
            do {
                let dest = try await CatalogCloneService.clone(project)
                await MainActor.run {
                    cloningProjectIDs.remove(project.id)
                    compareNotice = "Cloned \(project.name) to \(dest.path)."
                }
            } catch {
                await MainActor.run {
                    cloningProjectIDs.remove(project.id)
                    compareNotice = "Clone failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func removeClone(for project: ToolProject) {
        do {
            try CatalogCloneService.removeClone(project)
            behindProjectIDs.remove(project.id)
            compareNotice = "Moved the \(project.name) clone to the Trash."
        } catch {
            compareNotice = "Couldn't remove clone: \(error.localizedDescription)"
        }
    }

    /// Checks every cloned repo against its upstream (cheap `ls-remote`, no fetch)
    /// and flags the ones that are behind with a dot on their row. On-demand only.
    private func checkAllClonesForUpdates() {
        guard !isCheckingCloneUpdates else { return }
        let cloned = allProjects.filter { CatalogCloneService.isCloned($0) }
        guard !cloned.isEmpty else {
            compareNotice = "No cloned repositories to check."
            return
        }
        isCheckingCloneUpdates = true
        compareNotice = "Checking \(cloned.count) clone\(cloned.count == 1 ? "" : "s") for updates…"
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
                    compareNotice = "All clones are up to date."
                } else {
                    compareNotice = "\(behind.count) clone\(behind.count == 1 ? " has" : "s have") updates available. Press ⌘U to pull all."
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
            compareNotice = "No clones flagged — run Check Clones for Updates (⌘⇧U) first."
            return
        }
        isPullingClones = true
        compareNotice = "Pulling \(flagged.count) clone\(flagged.count == 1 ? "" : "s")…"
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
                compareNotice = pullSummary(updated: updated, skipped: skipped, failed: failed)
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
            compareNotice = "No duplicate repos found."
        } else {
            pendingDuplicateRemoval = victims
        }
    }

    private func performRemoveDuplicates() {
        let groups = duplicateGroups()
        guard !groups.isEmpty else { return }
        CatalogBackupService.writeSnapshot(allProjects) // recoverable via Restore from Backup
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
        catalogStateStore.refresh(projects: filteredProjects)
        compareNotice = "Removed \(removed) duplicate\(removed == 1 ? "" : "s"). A backup was saved."
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
        catalogStateStore.refresh(projects: filteredProjects)
        compareNotice = "Removed “\(name)” from the catalog."
    }

    private var compareButtonTitle: String {
        let count = compareSelectedProjectIDs.count
        return count > 0 ? "Compare (\(count))" : "Compare"
    }

    private var canCompareSelection: Bool {
        compareSelectedProjectIDs.count >= RepositoryCompareService.minRepositories
            && compareSelectedProjectIDs.count <= RepositoryCompareService.maxRepositories
    }

    private func toggleCompareSelection(for project: ToolProject) {
        if compareSelectedProjectIDs.contains(project.id) {
            compareSelectedProjectIDs.remove(project.id)
            return
        }
        guard compareSelectedProjectIDs.count < RepositoryCompareService.maxRepositories else {
            compareNotice = "You can compare up to \(RepositoryCompareService.maxRepositories) repositories."
            return
        }
        compareSelectedProjectIDs.insert(project.id)
    }

    private func compareSelectedProjects() {
        let selected = filteredProjects.filter { compareSelectedProjectIDs.contains($0.id) }
        var repositoryIDs: [String] = []
        var missing = 0

        for project in selected {
            let state = catalogStateStore.state(for: project)
            if state.analysisStatus == .ready, let repositoryID = state.repositoryID {
                repositoryIDs.append(repositoryID)
            } else if let repositoryID = IntelligenceRepositoryBridge.repositoryID(for: project) {
                repositoryIDs.append(repositoryID)
            } else {
                missing += 1
            }
        }

        guard repositoryIDs.count >= RepositoryCompareService.minRepositories else {
            compareNotice = missing > 0
                ? "Fetch intelligence for selected projects before comparing."
                : "Select at least \(RepositoryCompareService.minRepositories) projects with intelligence data."
            return
        }

        onCompareRepositoryIDs(Array(repositoryIDs.prefix(RepositoryCompareService.maxRepositories)))
        isCompareSelectMode = false
        compareSelectedProjectIDs = []
        if missing > 0 {
            compareNotice = "\(missing) selected project(s) had no ready intelligence and were skipped."
        } else {
            compareNotice = nil
        }
    }

    private func selectedProjects() -> [ToolProject] {
        filteredProjects.filter { compareSelectedProjectIDs.contains($0.id) }
    }

    private func batchGenerateRunbooks(force: Bool) {
        let selected = selectedProjects()
        guard !selected.isEmpty else { return }
        isBatchRunbookActionRunning = true
        let result = CatalogRunbookBatchService.generateRunbooks(for: selected, force: force)
        CatalogRunbookBatchService.emitBatchGenerateEvent(for: result)
        isBatchRunbookActionRunning = false
        compareNotice = result.summaryMessage
        catalogStateStore.refresh(projects: filteredProjects)
    }

    private func batchRegenerateStaleRunbooks() {
        let selected = selectedProjects()
        guard !selected.isEmpty else { return }
        isBatchRunbookActionRunning = true
        let result = CatalogRunbookBatchService.regenerateStaleRunbooks(for: selected)
        CatalogRunbookBatchService.emitBatchGenerateEvent(for: result)
        isBatchRunbookActionRunning = false
        compareNotice = result.summaryMessage
        catalogStateStore.refresh(projects: filteredProjects)
    }

    private func batchExportRunbooks() {
        let selected = selectedProjects()
        guard !selected.isEmpty else { return }
        isBatchRunbookActionRunning = true
        let result = CatalogRunbookBatchService.exportSelectedRunbooks(for: selected)
        isBatchRunbookActionRunning = false
        compareNotice = result.summaryMessage
        catalogStateStore.refresh(projects: filteredProjects)
    }

    private func enqueueRunbook(for repositoryID: String, force: Bool) {
            do {
            _ = try RepositoryRunbookService.enqueueGeneration(repositoryID: repositoryID, force: force)
            compareNotice = "Runbook generation queued."
            AppRefreshBus.emit(.queueUpdated)
            AppRefreshBus.emit(.catalogStateUpdated)
            catalogStateStore.refresh(projects: filteredProjects)
        } catch {
            compareNotice = error.localizedDescription
        }
    }

    private func fetchIntelligence(for project: ToolProject) {
        compareNotice = "Fetching intelligence for \(project.name)…"
        Task {
            let outcome = await CatalogIntelligenceIngestionService.fetchIntelligence(for: project)
            await MainActor.run {
                compareNotice = fetchOutcomeMessage(for: project.name, outcome: outcome)
                if case .started = outcome {
                    appRefreshStore.showIntelligenceRefreshComplete(started: 1)
                }
                catalogStateStore.refresh(projects: filteredProjects)
            }
        }
    }

    private func fetchIntelligenceForSelected() {
        let selected = selectedProjects()
        guard !selected.isEmpty else { return }
        isBatchFetchingIntelligence = true
        compareNotice = "Fetching intelligence for \(selected.count) selected project(s)…"
        Task {
            let result = await CatalogIntelligenceIngestionService.fetchIntelligence(for: selected)
            await MainActor.run {
                isBatchFetchingIntelligence = false
                compareNotice = result.summaryMessage
                if result.started > 0 {
                    appRefreshStore.showIntelligenceRefreshComplete(started: result.started)
                }
                catalogStateStore.refresh(projects: filteredProjects)
            }
        }
    }

    private func fetchIntelligenceForAllVisible() {
        let visible = filteredProjects
        guard !visible.isEmpty else { return }
        isBatchFetchingIntelligence = true
        compareNotice = "Fetching intelligence for visible projects…"
        Task {
            let result = await CatalogIntelligenceIngestionService.fetchIntelligence(for: visible)
            await MainActor.run {
                isBatchFetchingIntelligence = false
                compareNotice = result.summaryMessage
                if result.started > 0 {
                    appRefreshStore.showIntelligenceRefreshComplete(started: result.started)
                }
                catalogStateStore.refresh(projects: filteredProjects)
            }
        }
    }

    private func fetchOutcomeMessage(for name: String, outcome: CatalogIntelligenceFetchOutcome) -> String {
        switch outcome {
        case .started:
            return "Started intelligence fetch for \(name). Track progress in Queue."
        case .skippedAlreadyReady:
            return "\(name) already has intelligence data."
        case .skippedInProgress:
            return "\(name) is already queued or in progress."
        case .skippedInvalidURL:
            return "\(name) does not have a valid GitHub URL."
        case .skippedNoGitHubURL:
            return "\(name) needs a GitHub URL before intelligence can be fetched."
        case .failed(let message):
            return "Intelligence fetch failed for \(name): \(message)"
        }
    }

    private var filteredProjects: [ToolProject] {
        let bySidebar = applySidebarFilter(allProjects)
        let byRunbook = bySidebar.filter { project in
            runbookFilter == .all || runbookFilter.matches(catalogStateStore.state(for: project))
        }
        let bySearch = searchText.isEmpty
            ? byRunbook
            : byRunbook.filter { $0.matchesSearch(searchText) }
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

    private func applySidebarFilter(_ projects: [ToolProject]) -> [ToolProject] {
        guard let selection = sidebarSelection, selection.isCatalogFilter else { return projects }
        return projects.filter { selection.matchesCatalogFilter($0) }
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
        if runbookFilter != .all { return "doc.text" }
        if sidebarSelection?.isCatalogFilter == true { return "line.3.horizontal.decrease.circle" }
        return "tray"
    }

    private var catalogEmptyStateTitle: String {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty { return "No search results" }
        if runbookFilter != .all { return "No runbook matches" }
        if let sidebarSelection, sidebarSelection.isCatalogFilter {
            return "No projects in \(sidebarSelection.title)"
        }
        return "Your shelf is empty"
    }

    private var catalogEmptyStateMessage: String {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty {
            return "Nothing matched \"\(trimmedSearch)\". Try a different name, tag, or paste a GitHub URL."
        }
        if runbookFilter != .all {
            return "No visible projects match the \(runbookFilter.rawValue) filter. Try All Runbooks or fetch intelligence first."
        }
        if sidebarSelection?.isCatalogFilter == true {
            return "No projects match this filter yet. Capture more repos, or pick another sidebar filter."
        }
        return "Capture a GitHub repo to start building your personal open-source shelf."
    }

    private var catalogEmptyStateShowsCaptureActions: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            && runbookFilter == .all
            && sidebarSelection?.isCatalogFilter != true
            && allProjects.isEmpty
    }
}

struct ProjectRowView: View, Equatable {
    let project: ToolProject
    var catalogState: CatalogIntelligenceState
    var isCompareSelectMode: Bool = false
    var isCompareSelected: Bool = false
    var isSelected: Bool = false
    /// Intelligence badges (status chip + runbook badge) are a v2/Labs surface;
    /// hidden in the catalog-only default so rows stay clean.
    var showsIntelligence: Bool = false
    /// Captured status value so `.equatable()` detects a shelf move (status changes
    /// but the project reference stays the same, so we can't read it live in `==`).
    var statusKey: String = ""
    var isCloning: Bool = false
    var isClonedLocally: Bool = false
    /// Local clone is behind its upstream (updates available to pull).
    var isBehind: Bool = false
    var onSelect: (() -> Void)?
    var onCompareToggle: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    static func == (lhs: ProjectRowView, rhs: ProjectRowView) -> Bool {
        lhs.project.id == rhs.project.id
            && lhs.statusKey == rhs.statusKey
            && lhs.isCloning == rhs.isCloning
            && lhs.isClonedLocally == rhs.isClonedLocally
            && lhs.isBehind == rhs.isBehind
            && lhs.catalogState == rhs.catalogState
            && lhs.isCompareSelectMode == rhs.isCompareSelectMode
            && lhs.isCompareSelected == rhs.isCompareSelected
            && lhs.isSelected == rhs.isSelected
            && lhs.showsIntelligence == rhs.showsIntelligence
    }

    var body: some View {
        HStack(spacing: 10) {
            if isCompareSelectMode {
                Button(action: { onCompareToggle?() }) {
                    Image(systemName: isCompareSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isCompareSelected ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }

            ProjectIcon(project: project)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(project.shortDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if catalogState.runbookBadge != .noIntelligence,
                   let metadata = catalogState.compactMetadataLine {
                    Text(metadata)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
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

            if showsIntelligence {
                VStack(alignment: .trailing, spacing: 4) {
                    if catalogState.analysisStatus != .ready && catalogState.analysisStatus != .notFetched {
                        IntelligenceStatusChip(snapshot: catalogState.intelligenceSnapshot)
                    }
                    CatalogRunbookBadgeView(badge: catalogState.runbookBadge,
                                            tooltip: catalogState.tooltipText)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .onTapGesture {
            if isCompareSelectMode {
                onCompareToggle?()
            } else {
                onSelect?()
            }
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
    let onCatalogQuickAction: (Notification) -> Void
    let onSetRunbookFilter: (Notification) -> Void
    let onToggleCompareMode: () -> Void
    let onFetchAllIntelligence: () -> Void
    let onCompareSelected: () -> Void
    let onCancelCompareMode: () -> Void
    let onCheckCloneUpdates: () -> Void
    let onPullCloneUpdates: () -> Void
    let onMoveSelectedToShelf: (Notification) -> Void
    let onCloneStatusKnown: (Notification) -> Void
    let onRemoveDuplicates: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: AppQuickActionCenter.catalogActionName), perform: onCatalogQuickAction)
            .onReceive(NotificationCenter.default.publisher(for: .setCatalogRunbookFilter), perform: onSetRunbookFilter)
            .onReceive(NotificationCenter.default.publisher(for: .toggleCatalogCompareMode)) { _ in onToggleCompareMode() }
            .onReceive(NotificationCenter.default.publisher(for: .catalogFetchAllIntelligence)) { _ in onFetchAllIntelligence() }
            .onReceive(NotificationCenter.default.publisher(for: .catalogCompareSelected)) { _ in onCompareSelected() }
            .onReceive(NotificationCenter.default.publisher(for: .catalogCancelCompareMode)) { _ in onCancelCompareMode() }
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
    case name
    case stars

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .name: "Name (A–Z)"
        case .stars: "Most Stars"
        }
    }

    var icon: String {
        switch self {
        case .recentlyAdded: "clock"
        case .name: "textformat"
        case .stars: "star"
        }
    }

    func sorted(_ projects: [ToolProject]) -> [ToolProject] {
        switch self {
        case .recentlyAdded:
            return projects.sorted { $0.addedDate > $1.addedDate }
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
