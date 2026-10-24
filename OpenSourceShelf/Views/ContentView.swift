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
private enum SheetPresentation {
    /// Bumped on every attempt, so a recovery check scheduled for an earlier
    /// attempt can tell it has been superseded and stay out of the way.
    static var generation = 0
}

@MainActor
func presentSheetAfterEndingTextEditing(_ present: @escaping () -> Void) {
    for window in NSApp.windows where window.firstResponder is NSTextView {
        window.makeFirstResponder(nil)
    }
    SheetPresentation.generation += 1
    presentOnceRemoteViewsDetach(present,
                                 attemptsLeft: 12,
                                 generation: SheetPresentation.generation)
}

@MainActor
private func presentOnceRemoteViewsDetach(_ present: @escaping () -> Void,
                                          attemptsLeft: Int,
                                          generation: Int) {
    guard attemptsLeft > 0, textInputRemoteViewIsOnScreen() else {
        DispatchQueue.main.async {
            present()
            confirmSheetAppeared(generation: generation, checksLeft: 8)
        }
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        presentOnceRemoteViewsDetach(present,
                                     attemptsLeft: attemptsLeft - 1,
                                     generation: generation)
    }
}

/// Recovery, take two. This used to sample once at 1.2s: if no sheet window was
/// on screen at that instant it declared a wedge and posted
/// `.verifyWedgedSheets`, whose handler nils every sheet binding — including the
/// request that had *just* been made. Capture from the ⌘K palette is the slow
/// path (up to 600ms of remote-view polling, then a second sheet that cannot
/// appear until the palette finishes dismissing), so a valid presentation could
/// cross 1.2s and be cancelled by its own watchdog. The sheet never opened, and
/// clearing state mid-presentation left the presenter wedged for good.
///
/// A real wedge is permanent; a slow presentation is not. So poll rather than
/// sample — any check that sees a sheet stands down, and only a sheet that never
/// arrives across the whole window is treated as a wedge.
@MainActor
private func confirmSheetAppeared(generation: Int, checksLeft: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        // A newer attempt owns the presenter now — this check is stale, and
        // clearing state here would cancel that newer request.
        guard generation == SheetPresentation.generation else { return }
        if NSApp.windows.contains(where: { $0.isVisible && $0.isSheet }) { return }
        guard checksLeft > 1 else {
            NotificationCenter.default.post(name: .verifyWedgedSheets, object: nil)
            return
        }
        confirmSheetAppeared(generation: generation, checksLeft: checksLeft - 1)
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

/// Catches ⌘V in the main window when no text field has focus, and hands a
/// GitHub repo link from the clipboard to Quick Capture. Anything else — a text
/// field focused, a sheet up, a non-GitHub clipboard — passes through untouched,
/// so normal pasting never changes.
///
/// Hangs off `viewDidMoveToWindow` (like MainWindowChromeConfigurator) so it
/// only reacts to key events for *this* window, not Settings.
struct ClipboardCaptureMonitor: NSViewRepresentable {
    var onPasteRepoURL: (String) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onPasteRepoURL = onPasteRepoURL
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onPasteRepoURL = onPasteRepoURL
    }

    final class MonitorView: NSView {
        var onPasteRepoURL: ((String) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handles(event) else { return event }
                return nil
            }
        }

        private func handles(_ event: NSEvent) -> Bool {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v",
                  let window, event.window === window,
                  window.attachedSheet == nil,
                  !(window.firstResponder is NSText),
                  let text = NSPasteboard.general.string(forType: .string)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.contains(where: \.isNewline),
                  GitHubRepositoryURL.ownerAndRepo(from: text) != nil
            else { return false }
            onPasteRepoURL?(text)
            return true
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

struct QuickCaptureRequest: Identifiable {
    let id = UUID()
    let url: String
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var listSelection: CatalogListSelection?
    @State private var searchText: String = ""
    @State private var sidebarSelection: ShelfSelection? = .builtin(.allProjects)
    @State private var quickCaptureRequest: QuickCaptureRequest?
    @State private var showingCommandPalette: Bool = false
    @State private var showingImportURLs: Bool = false
    @State private var showingRestoreBackup: Bool = false
    /// The "What's new" notes while that sheet is up; nil = no sheet.
    @State private var whatsNewLines: [WhatsNew.Line]?
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
    /// Bumped when categories are merged (`CategoryClassifier.mergedCategories`).
    private static let categoryMergeVersion = 1
    @AppStorage("reshelf.categoryMergeVersion") private var storedCategoryMergeVersion = 0

    var body: some View {
        catalogRootStack
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
                    initialURL: request.url,
                    onOpenExisting: { project in revealProject(project.id) }
                )
            }
            // reshelf://add?url=… from another app (Undrdr Drop's "Send to reshelf"):
            // saves straight into The Collector, no sheet.
            .onOpenURL { link in
                guard let url = LinkCaptureService.githubURL(from: link) else { return }
                let context = modelContext
                Task { @MainActor in
                    switch await LinkCaptureService.capture(url, context: context) {
                    case .added(let project):
                        listSelection = .project(project.id)
                    case .duplicate(let project):
                        revealProject(project.id)
                    case .failed(let message):
                        NotificationCenter.default.post(name: .catalogStatusNotice, object: message)
                    }
                }
            }
            // Reuse this window for incoming links instead of opening a new one.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
                showingCommandPalette = false
                showingImportURLs = false
                showingRestoreBackup = false
                whatsNewLines = nil
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
            .onReceive(NotificationCenter.default.publisher(for: .showWhatsNew)) { _ in
                guard let lines = WhatsNew.notes(for: WhatsNew.currentVersion) else { return }
                presentSheetAfterEndingTextEditing { whatsNewLines = lines }
            }
            .sheet(isPresented: Binding(get: { whatsNewLines != nil },
                                        set: { if !$0 { closeWhatsNew() } })) {
                WhatsNewSheet(appName: "reshelf", lines: whatsNewLines ?? []) { closeWhatsNew() }
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
            // Auto-backup also watches the count (adds and deletes that somehow
            // skipped CatalogSave) and when the app leaves the foreground.
            // In-place edits are covered by CatalogSave.save, which schedules
            // the same 2-second snapshot. A bulk import stays one snapshot.
            .onChange(of: allProjects.count) { oldCount, newCount in
                CatalogBackupService.scheduleSnapshot(from: modelContext)
                CatalogBackupService.noteProjectCount(old: oldCount, new: newCount)
            }
            .onChange(of: allFolders.count) { _, _ in
                CatalogBackupService.scheduleSnapshot(from: modelContext)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    CatalogBackupService.scheduleSnapshot(from: modelContext)
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
                CatalogBackupService.writeSnapshotNow(allProjects, folders: allFolders)
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

    private func closeWhatsNew() {
        WhatsNew.markSeen()
        whatsNewLines = nil
    }

    private func handleContentAppear() {
        // Before this launch writes its own backup: existing backups mean an
        // update from a version that had no What's new yet, not a first install.
        if WhatsNew.shouldShow(usedBefore: !CatalogBackupService.snapshotURLs().isEmpty),
           let lines = WhatsNew.notes(for: WhatsNew.currentVersion) {
            presentSheetAfterEndingTextEditing { whatsNewLines = lines }
        }
        // Safety net: if the catalog comes up empty but a backup with data exists,
        // restore it instead of seeding defaults over a real (momentarily missing)
        // catalog. Only seed when there's genuinely nothing to restore.
        let restored = CatalogBackupService.restoreIfCatalogEmpty(context: modelContext)
        if !restored, !CatalogBackupService.emptiedByUser {
            SeedData.seedIfNeeded(context: modelContext)
        }
        // Once: what the move from the old ~/OpenSourceShelf folder left there.
        if let notice = LegacyNameMigration.leftBehindNotice {
            UserDefaults.standard.removeObject(forKey: LegacyNameMigration.noticeKey)
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Some old files stayed in ~/OpenSourceShelf"
                alert.informativeText = notice
                alert.runModal()
            }
        }
        if let message = CatalogStoreLocation.recoveryMessage(restored: restored) {
            let title = CatalogStoreLocation.openFailure != nil
                ? "Catalog file can't be opened"
                : (restored ? "Catalog restored from backup" : "Catalog file replaced")
            CatalogStoreLocation.recovery = nil
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.runModal()
            }
        }
        // Reclassify before snapshotting so the launch backup reflects the
        // corrected categories (not the pre-reclassify state).
        // Fetch here, not from @Query: a restore that just ran has written
        // the rows, and the query can still be the empty list from launch.
        mergeCategoriesIfNeeded()
        reclassifyProjectsIfNeeded()
        repairSchemelessLinks()
        let projects = freshProjects()
        let folders = freshFolders()
        // Clones an older build made in a custom folder get their marker.
        CatalogCloneService.adoptLegacyClonesIfNeeded(projects)
        // Tidy any legacy flat clones into their category subfolders.
        CatalogCloneService.migrateClonesIntoCategoryFolders(projects)
        CatalogBackupService.writeSnapshot(projects, folders: folders)
        ensureCatalogSelectionIfNeeded()
        applyColumnVisibility()
    }

    private var commandPaletteProjectSelection: Binding<UUID?> {
        Binding(
            get: { listSelection?.projectID },
            set: { newValue in
                if let newValue {
                    // A sidebar filter or a search can hide the row. Reveal
                    // clears both, the same way Show in List does.
                    revealProject(newValue)
                }
            }
        )
    }

    /// Shows a project in the list no matter what's filtered: back to All
    /// Projects, search cleared, row selected and scrolled into view.
    private func revealProject(_ id: UUID) {
        sidebarSelection = .builtin(.allProjects)
        searchText = ""
        listSelection = .project(id)
        // Next tick: if the list was showing its empty state (a search with no
        // hits), the scrollable rows only exist after this reset renders.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .revealProjectInList, object: id)
        }
    }

    /// ⌘V with a GitHub repo link on the clipboard (and no text field focused):
    /// open Quick Capture with it. The sheet itself handles "already shelved".
    private func captureFromClipboard(_ url: String) {
        guard quickCaptureRequest == nil, !showingCommandPalette else { return }
        presentSheetAfterEndingTextEditing {
            quickCaptureRequest = QuickCaptureRequest(url: url)
        }
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
        .background(ClipboardCaptureMonitor(onPasteRepoURL: captureFromClipboard))
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
        SidebarColumnHost(current: sidebarSelection, selection: $sidebarSelection)
        .equatable()
        .id("catalog-sidebar")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // macOS 26: no paint here, so the sidebar shows its Liquid Glass.
        .flatColumnBackgroundBeforeTahoe()
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

    /// Rows imported before WebLink existed can hold "github.com/…" without a
    /// scheme. Only adds "https://"; never changes a link that has one.
    /// The catalog as stored right now. `@Query` can still be empty on the
    /// turn a launch restore inserted the rows.
    private func freshProjects() -> [ToolProject] {
        (try? modelContext.fetch(FetchDescriptor<ToolProject>())) ?? allProjects
    }

    private func freshFolders() -> [CatalogFolder] {
        (try? modelContext.fetch(FetchDescriptor<CatalogFolder>())) ?? allFolders
    }

    private func repairSchemelessLinks() {
        var changed = false
        for project in freshProjects() {
            let github = WebLink.normalized(project.githubURL)
            let website = WebLink.normalized(project.websiteURL)
            if github != project.githubURL { project.githubURL = github; changed = true }
            if website != project.websiteURL { project.websiteURL = website; changed = true }
        }
        if changed { CatalogSave.save(modelContext) }
    }

    /// Once per merge version: back up, rename rows in a merged category
    /// (Kika asked for these merges, so overwriting the old names is the point),
    /// then move their clone folders to match.
    private func mergeCategoriesIfNeeded() {
        guard storedCategoryMergeVersion < Self.categoryMergeVersion else { return }
        let merges = CategoryClassifier.mergedCategories
        let projects = freshProjects()
        let affected = projects.filter {
            merges[$0.category.trimmingCharacters(in: .whitespaces)] != nil
        }
        if !affected.isEmpty {
            CatalogBackupService.writeSnapshot(projects, folders: freshFolders())
            for project in affected {
                if let merged = merges[project.category.trimmingCharacters(in: .whitespaces)] {
                    project.category = merged
                }
            }
            // A failed save must not move clone folders or mark the merge done.
            // The next launch tries again.
            guard CatalogSave.save(modelContext, "the merged categories") else { return }
        }
        CatalogCloneService.mergeCategoryFolders(merges)
        storedCategoryMergeVersion = Self.categoryMergeVersion
    }

    private func reclassifyProjectsIfNeeded() {
        let force = storedClassifierVersion < Self.classifierVersion
        let projects = freshProjects()
        if force {
            CatalogBackupService.writeSnapshot(projects, folders: freshFolders())
        }
        var changed = false
        for project in projects {
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
            CatalogSave.save(modelContext)
        }
        storedClassifierVersion = Self.classifierVersion
    }
}

private struct ContentViewNotificationHandlers: ViewModifier {
    @Binding var sidebarSelection: ShelfSelection?
    @Binding var listSelection: CatalogListSelection?
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
            .onReceive(NotificationCenter.default.publisher(for: .selectSidebarTag)) { notification in
                guard let key = notification.object as? String, !key.isEmpty else { return }
                sidebarSelection = .tag(key)
            }
            .onAppear(perform: onAppear)
    }
}
