import AppKit
import SwiftUI
import SwiftData

/// Posted by the sheet watchdog when a requested sheet never materialized — the
/// caught ViewBridge exception left SwiftUI believing a sheet is presented, so
/// every later presentation queues behind a phantom. Views that drive sheets
/// listen and clear any sheet state that claims to be active without a visible
/// sheet window, which un-wedges presentation for the next attempt.
extension Notification.Name {
    static let verifyWedgedSheets = Notification.Name("reshelf.verifyWedgedSheets")
}

/// Runs a sheet presentation only after tearing down any text-input remote views.
///
/// macOS attaches an autofill/completion popup (an `NSRemoteView` hosted by
/// SafariPlatformSupport) to focused text fields. If that popup is still wired to
/// a field when a sheet window orders on screen, ViewBridge fails an assertion and
/// throws `NSInternalInconsistencyException` from inside
/// `-[NSWindow _beginWindowBlockingModalSessionForSheet:...]`. AppKit catches the
/// exception at the event loop, but SwiftUI is left believing a sheet is
/// presented, and every subsequent sheet queues forever behind the phantom
/// ("Currently, only presenting a single sheet is supported…").
///
/// Two defenses, both needed (1.3.1 shipped only a one-runloop-turn deferral and
/// the wedge still occurred during rapid serial Quick Captures):
/// 1. Prevention — end editing everywhere, then WAIT until no ViewBridge remote
///    view is on screen (polling, bounded) before presenting; the popup detaches
///    asynchronously over XPC, so a fixed one-turn delay is a race.
/// 2. Recovery — after presenting, verify a sheet window actually appeared; if
///    not, post `.verifyWedgedSheets` so state owners can reset (see above).
@MainActor
func presentSheetAfterEndingTextEditing(_ present: @escaping () -> Void) {
    for window in NSApp.windows where window.firstResponder is NSTextView {
        window.makeFirstResponder(nil)
    }
    presentOnceRemoteViewsDetach(present, attemptsLeft: 12)
}

@MainActor
private func presentOnceRemoteViewsDetach(_ present: @escaping () -> Void, attemptsLeft: Int) {
    guard attemptsLeft > 0, textInputRemoteViewIsOnScreen() else {
        DispatchQueue.main.async {
            present()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let sheetVisible = NSApp.windows.contains { $0.isVisible && $0.isSheet }
                if !sheetVisible {
                    NotificationCenter.default.post(name: .verifyWedgedSheets, object: nil)
                }
            }
        }
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        presentOnceRemoteViewsDetach(present, attemptsLeft: attemptsLeft - 1)
    }
}

/// Whether any visible window hosts a ViewBridge remote view (the autofill /
/// text-completion popup). Class-name sniffing is the only handle we have on
/// these private views; matching "RemoteView" covers NSRemoteView and the
/// TUINSRemoteViewController-hosted variants.
@MainActor
private func textInputRemoteViewIsOnScreen() -> Bool {
    func containsRemoteView(_ view: NSView, depth: Int) -> Bool {
        if depth > 6 { return false }
        if String(describing: type(of: view)).contains("RemoteView") { return true }
        return view.subviews.contains { containsRemoteView($0, depth: depth + 1) }
    }
    return NSApp.windows.contains { window in
        guard window.isVisible else { return false }
        if String(describing: type(of: window)).contains("TUINS") { return true }
        guard let content = window.contentView else { return false }
        return containsRemoteView(content, depth: 0)
    }
}

// Layout model: 2-column NavigationSplitView (sidebar | detail).
// The detail column contains an HStack[list + optional inspector].
// columnVisibility controls only the sidebar (.all = visible, .doubleColumn = hidden).
// showsInspectorColumn toggles the inspector inside the HStack — the list expands naturally.

struct QuickCaptureRequest: Identifiable {
    let id = UUID()
    let url: String
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var listSelection: CatalogListSelection?
    @State private var searchText: String = ""
    @State private var sidebarSelection: ShelfSelection? = .builtin(.allProjects)
    @State private var showingAddSheet: Bool = false
    @State private var quickCaptureRequest: QuickCaptureRequest?
    @State private var showingCommandPalette: Bool = false
    @State private var showingImportURLs: Bool = false
    @State private var showingRestoreBackup: Bool = false
    @State private var importCatalogRequest: ImportCatalogRequest?
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingCaptureURL: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSidebarVisible = true
    @State private var showsInspectorColumn = true
    @AppStorage("inspectorPanelWidth") private var inspectorWidth: Double = ShelfLayout.inspectorWidth.ideal
    @State private var isResizingInspector = false
    @State private var isApplyingColumnVisibility = false
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]
    @Query(sort: \CatalogFolder.sortIndex) private var allFolders: [CatalogFolder]

    /// Bump when CategoryClassifier gets meaningfully smarter: the next launch
    /// takes a backup and re-runs the fill pass once. Only empty / raw-language
    /// categories are ever (re)scored — existing assignments, whether classifier-
    /// produced or hand-sorted, are never overwritten (they're indistinguishable).
    private static let classifierVersion = 4
    @AppStorage("reshelf.classifierVersion") private var storedClassifierVersion = 1

    var body: some View {
        catalogRootStack
            .sheet(isPresented: $showingAddSheet) {
                AddProjectSheet(isPresented: $showingAddSheet, onSave: { project in
                    listSelection = .project(project.id)
                })
            }
            .sheet(item: $quickCaptureRequest) { request in
                QuickCaptureSheet(
                    isPresented: Binding(
                        get: { quickCaptureRequest != nil },
                        set: { if !$0 { quickCaptureRequest = nil } }
                    ),
                    onSave: { project in
                        listSelection = .project(project.id)
                        searchText = ""
                    },
                    initialURL: request.url
                )
            }
            .sheet(isPresented: $showingCommandPalette, onDismiss: handleCommandPaletteDismiss) {
                CommandPaletteView(
                    isPresented: $showingCommandPalette,
                    searchText: $searchText,
                    selectedProjectID: commandPaletteProjectSelection,
                    quickCaptureURL: $pendingCaptureURL
                )
            }
            .modifier(ContentViewNotificationHandlers(
                sidebarSelection: $sidebarSelection,
                listSelection: $listSelection,
                showingAddSheet: $showingAddSheet,
                showingCommandPalette: $showingCommandPalette,
                quickCaptureRequest: $quickCaptureRequest,
                appRefreshStore: appRefreshStore,
                onToggleSidebar: toggleSidebarColumn,
                onToggleInspector: toggleInspectorColumn,
                onSelectSidebarItem: selectSidebarItem,
                onAppear: handleContentAppear
            ))
            .onReceive(NotificationCenter.default.publisher(for: .exportCatalog)) { _ in
                CatalogExportService.presentExportPanel(projects: allProjects, folders: allFolders)
            }
            // Sheet-wedge recovery: a caught ViewBridge exception mid-presentation
            // leaves SwiftUI believing a sheet is up when none is on screen, and
            // every later sheet queues behind the phantom. Clear any state that
            // claims to be presenting without a visible sheet window so the next
            // attempt presents cleanly (previously required a force-quit).
            .onReceive(NotificationCenter.default.publisher(for: .verifyWedgedSheets)) { _ in
                guard !NSApp.windows.contains(where: { $0.isVisible && $0.isSheet }) else { return }
                showingAddSheet = false
                showingCommandPalette = false
                showingImportURLs = false
                showingRestoreBackup = false
                importCatalogRequest = nil
                quickCaptureRequest = nil
            }
            // Clone badges are derived from a per-launch disk index; returning to
            // the app is when out-of-app changes (Finder moves, Trash restores,
            // CLI clones) can have happened — rescan so badges don't go stale.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                CatalogCloneService.invalidateCloneIndex()
                appRefreshStore.handle(.catalogStateUpdated)
            }
            .onReceive(NotificationCenter.default.publisher(for: .importURLs)) { _ in
                presentSheetAfterEndingTextEditing { showingImportURLs = true }
            }
            .sheet(isPresented: $showingImportURLs) {
                ImportURLsSheet(isPresented: $showingImportURLs)
            }
            .onReceive(NotificationCenter.default.publisher(for: .restoreBackup)) { _ in
                presentSheetAfterEndingTextEditing { showingRestoreBackup = true }
            }
            .sheet(isPresented: $showingRestoreBackup) {
                RestoreBackupSheet(isPresented: $showingRestoreBackup)
            }
            // The open panel runs first, with no sheet up — running a modal
            // panel from inside a sheet is what wedges sheet presentation.
            .onReceive(NotificationCenter.default.publisher(for: .importCatalog)) { _ in
                guard let picked = CatalogImportService.presentOpenPanel() else { return }
                presentSheetAfterEndingTextEditing {
                    importCatalogRequest = ImportCatalogRequest(
                        url: picked.url, rows: picked.rows, folders: picked.folders)
                }
            }
            .sheet(item: $importCatalogRequest) { request in
                ImportCatalogSheet(
                    request: request,
                    isPresented: Binding(
                        get: { importCatalogRequest != nil },
                        set: { if !$0 { importCatalogRequest = nil } }
                    )
                )
            }
            // Auto-backup: snapshot whenever the project count changes (add/remove)
            // and when the app goes to the background (catches in-place edits).
            .onChange(of: allProjects.count) { _, _ in
                CatalogBackupService.writeSnapshot(allProjects, folders: allFolders)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    CatalogBackupService.writeSnapshot(allProjects, folders: allFolders)
                }
            }
            // …and on quit. `scenePhase` is not reliably delivered before the
            // process goes away, so an edit that changed values without changing
            // the project count could be lost: neither trigger above fired, and
            // the newest snapshot stayed older than the change. `willTerminate`
            // runs synchronously while the app is still alive, which is exactly
            // the window a last write needs.
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification)) { _ in
                CatalogBackupService.writeSnapshot(allProjects, folders: allFolders)
            }
    }

    private var catalogRootStack: some View {
        VStack(spacing: 0) {
            catalogSplitView
        }
    }

    private func handleCommandPaletteDismiss() {
        if !pendingCaptureURL.isEmpty {
            let url = pendingCaptureURL
            pendingCaptureURL = ""
            // The palette sheet (with its focused search field) is tearing down
            // right now — presenting the capture sheet synchronously is the
            // hottest path for the ViewBridge modal-session freeze.
            presentSheetAfterEndingTextEditing {
                quickCaptureRequest = QuickCaptureRequest(url: url)
            }
        }
    }

    private func handleContentAppear() {
        // Safety net: if the catalog comes up empty but a backup with data exists,
        // restore it instead of seeding defaults over a real (momentarily missing)
        // catalog. Only seed when there's genuinely nothing to restore.
        if !CatalogBackupService.restoreIfCatalogEmpty(context: modelContext) {
            SeedData.seedIfNeeded(context: modelContext)
        }
        // Reclassify before snapshotting so the launch backup reflects the
        // corrected categories (not the pre-reclassify state).
        reclassifyProjectsIfNeeded()
        // Tidy any legacy flat clones into their category subfolders.
        CatalogCloneService.migrateClonesIntoCategoryFolders(allProjects)
        CatalogBackupService.writeSnapshot(allProjects, folders: allFolders)
        ensureCatalogSelectionIfNeeded()
        applyColumnVisibility()
    }

    private var commandPaletteProjectSelection: Binding<UUID?> {
        Binding(
            get: { listSelection?.projectID },
            set: { newValue in
                if let newValue {
                    listSelection = .project(newValue)
                }
            }
        )
    }

    private func selectSidebarItem(_ item: SidebarItem) {
        sidebarSelection = .builtin(item)
    }

    private var catalogSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            catalogDetailHStack
        }
        .navigationTitle("")
        // Drop NavigationSplitView's automatic sidebar-toggle toolbar item: it
        // forces an otherwise-empty title bar band. Our own toggle lives in the
        // list header instead, so the header row can rise to the very top.
        .toolbar(removing: .sidebarToggle)
        .hidesTopScrollEdgeEffect()
        .background {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
        .background(MainWindowChromeConfigurator())
        .onChange(of: columnVisibility) { _, newValue in
            guard !isApplyingColumnVisibility else { return }
            isSidebarVisible = (newValue == .all)
        }
        .id("catalog-split-view")
    }

    // Detail column: list always fills; inspector slides in at the trailing edge.
    // ResizeDivider uses AppKit mouse events — immune to NavigationSplitView gesture interception.
    private var catalogDetailHStack: some View {
        HStack(spacing: 0) {
            catalogPrimaryColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            if showsTrailingColumn {
                ResizeDivider(
                    width: inspectorWidthBinding,
                    isDragging: $isResizingInspector,
                    minWidth: ShelfLayout.inspectorWidth.min,
                    maxWidth: ShelfLayout.inspectorWidth.max
                )
                .frame(width: 8)
                .frame(maxHeight: .infinity)

                trailingPanel
                    .frame(maxHeight: .infinity)
                    .frame(width: CGFloat(inspectorWidth))
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipped()
            }
        }
        .animation(isResizingInspector ? nil : .easeInOut(duration: 0.2), value: showsTrailingColumn)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Mirror the sidebar: the column headers are the title bar, so the detail
        // area lays out from the window's top edge (keeps all header dividers on
        // one line and leaves no exposed title-bar band above the content).
        .ignoresSafeArea(.container, edges: .top)
        // Must be applied inside the column, not on the NavigationSplitView —
        // the pocket is driven per split item.
        .hidesTopScrollEdgeEffect()
    }

    /// Bridges the @AppStorage Double width to the CGFloat binding ResizeDivider expects.
    private var inspectorWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(inspectorWidth) },
            set: { inspectorWidth = Double($0) }
        )
    }

    /// The trailing column follows the ⌘I inspector toggle.
    private var showsTrailingColumn: Bool {
        guard showsInspectorColumn else { return false }
        return listSelection != nil
    }

    @ViewBuilder
    private var trailingPanel: some View {
        detailColumn
    }

    private func toggleSidebarColumn() {
        // Route through AppKit — same mechanism the toolbar sidebar button uses.
        // Programmatic columnVisibility writes are silently ignored on macOS.
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        // Re-flatten the divider: showing the sidebar can restore the system
        // drop shadow on the split item.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            ShelfWindowChrome.flattenSidebarDivider(in: window, attemptsRemaining: 4)
        }
    }

    private func toggleInspectorColumn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showsInspectorColumn.toggle()
        }
    }

    private func applyColumnVisibility() {
        isApplyingColumnVisibility = true
        withAnimation(.easeInOut(duration: 0.2)) {
            columnVisibility = isSidebarVisible ? .all : .doubleColumn
        }
        DispatchQueue.main.async {
            isApplyingColumnVisibility = false
        }
    }

    private var sidebarColumn: some View {
        SidebarView(selection: $sidebarSelection) { projectID in
            listSelection = .project(projectID)
        }
        .id("catalog-sidebar")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(
            min: ShelfLayout.sidebarWidth.min,
            ideal: ShelfLayout.sidebarWidth.ideal,
            max: ShelfLayout.sidebarWidth.max
        )
    }

    private func ensureCatalogSelectionIfNeeded() {
        guard usesProjectListColumn else { return }
        guard listSelection == nil, let first = allProjects.first else { return }
        listSelection = .project(first.id)
    }

    private var usesProjectListColumn: Bool {
        switch sidebarSelection?.builtinItem {
        case .settings:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private var catalogPrimaryColumn: some View {
        ProjectListView(
            listSelection: $listSelection,
            searchText: $searchText,
            sidebarSelection: $sidebarSelection,
            showingAddSheet: $showingAddSheet,
            needsTrafficLightInset: !isSidebarVisible,
            onQuickCapture: {
                presentSheetAfterEndingTextEditing {
                    quickCaptureRequest = QuickCaptureRequest(url: "")
                }
            }
        )
        .id("catalog-project-list")
    }

    @ViewBuilder
    private var detailColumn: some View {
        CatalogInspectorPane(
            listSelection: listSelection,
            onSelectionChange: { listSelection = $0 }
        )
    }

    private var selectedProject: ToolProject? {
        guard let id = listSelection?.projectID else { return nil }
        return allProjects.first(where: { $0.id == id })
    }

    private func openCatalogRepository(_ repositoryID: String) {
        guard let repository = try? IntelligenceDatabase.shared.fetchRepository(id: repositoryID) else { return }
        if let project = allProjects.first(where: {
            !$0.githubURL.isEmpty && $0.githubURL == repository.githubURL
        }) ?? allProjects.first(where: { $0.name == repository.name }) {
            listSelection = .project(project.id)
            sidebarSelection = .builtin(.allProjects)
        }
    }

    private func reclassifyProjectsIfNeeded() {
        let force = storedClassifierVersion < Self.classifierVersion
        if force {
            CatalogBackupService.writeSnapshot(allProjects, folders: allFolders)
        }
        var changed = false
        for project in allProjects {
            // Empty / raw-language categories are always re-scored; classifier-
            // produced ones only on a version bump; user-typed labels never.
            guard CategoryClassifier.shouldReclassify(project.category, force: force) else { continue }
            let newCategory = CategoryClassifier.reclassify(
                tags: project.tags,
                description: project.shortDescription.isEmpty ? project.longDescription : project.shortDescription,
                currentCategory: project.category,
                name: project.name,
                language: nil,
                force: force
            )
            if newCategory != project.category {
                project.category = newCategory
                changed = true
            }
        }
        if changed {
            try? modelContext.save()
        }
        storedClassifierVersion = Self.classifierVersion
    }
}

private struct ContentViewNotificationHandlers: ViewModifier {
    @Binding var sidebarSelection: ShelfSelection?
    @Binding var listSelection: CatalogListSelection?
    @Binding var showingAddSheet: Bool
    @Binding var showingCommandPalette: Bool
    @Binding var quickCaptureRequest: QuickCaptureRequest?
    let appRefreshStore: AppRefreshStore
    let onToggleSidebar: () -> Void
    let onToggleInspector: () -> Void
    let onSelectSidebarItem: (SidebarItem) -> Void
    let onAppear: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarColumn)) { _ in
                onToggleSidebar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspectorColumn)) { _ in
                onToggleInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .addProject)) { _ in
                presentSheetAfterEndingTextEditing { showingAddSheet = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickCapture)) { _ in
                presentSheetAfterEndingTextEditing {
                    quickCaptureRequest = QuickCaptureRequest(url: "")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
                presentSheetAfterEndingTextEditing { showingCommandPalette = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppRefreshBus.notificationName)) { notification in
                guard let event = AppRefreshEvent.decode(from: notification) else { return }
                appRefreshStore.handle(event)
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectSidebarItem)) { notification in
                guard let raw = notification.userInfo?["item"] as? String,
                      let item = SidebarItem(rawValue: raw) else { return }
                onSelectSidebarItem(item)
            }
            .onAppear(perform: onAppear)
    }
}
