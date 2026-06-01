import SwiftUI
import SwiftData
import AppKit
import Darwin

/// One-time migration from the app's former name ("OpenSourceShelf") to "reshelf".
/// The Xcode target/module and bundle ID intentionally stay `OpenSourceShelf` /
/// `com.kika.opensourceshelf`, so the SwiftData catalog (default store, keyed by
/// bundle ID) and the UserDefaults domain are unchanged — only the on-disk data
/// folder and our own prefixed keys move.
private enum LegacyNameMigration {
    static func runIfNeeded() {
        migrateDataFolder()
        migrateUserDefaults()
    }

    /// `~/OpenSourceShelf` → `~/reshelf` (intelligence DB + cloned repos).
    private static func migrateDataFolder() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let old = home.appendingPathComponent("OpenSourceShelf", isDirectory: true)
        let new = home.appendingPathComponent("reshelf", isDirectory: true)
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.moveItem(at: old, to: new)
        } catch {
            #if DEBUG
            print("[reshelf] Data folder migration failed: \(error)")
            #endif
        }
    }

    /// `OpenSourceShelf.*` keys → `reshelf.*` (same defaults domain; bundle ID unchanged).
    private static func migrateUserDefaults() {
        let defaults = UserDefaults.standard
        let pairs = [
            ("OpenSourceShelf.ollamaBaseURL", "reshelf.ollamaBaseURL"),
            ("OpenSourceShelf.ollamaSelectedModel", "reshelf.ollamaSelectedModel"),
            ("OpenSourceShelf.autoGenerateRunbookAfterIntelligence", "reshelf.autoGenerateRunbookAfterIntelligence"),
            ("OpenSourceShelf.cloneRootPath", "reshelf.cloneRootPath")
        ]
        for (old, new) in pairs {
            guard defaults.object(forKey: new) == nil,
                  let value = defaults.object(forKey: old) else { continue }
            defaults.set(value, forKey: new)
            defaults.removeObject(forKey: old)
        }
    }
}

/// Resolves the SwiftData catalog store to an app-specific path under `~/reshelf`
/// (next to the intelligence DB) instead of the shared, non-namespaced
/// `~/Library/Application Support/default.store`. On first run it copies any
/// existing shared store over so no data is left behind.
private enum CatalogStoreLocation {
    static func migrateAndResolve() -> URL {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("reshelf", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let newURL = root.appendingPathComponent("catalog.store")

        // One-time migration from the shared default store (and its -wal/-shm
        // sidecars). Only runs if we haven't created the app-specific store yet.
        if !fm.fileExists(atPath: newURL.path),
           let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let oldBase = appSupport.appendingPathComponent("default.store").path
            for suffix in ["", "-wal", "-shm"] {
                let src = oldBase + suffix
                let dst = newURL.path + suffix
                if fm.fileExists(atPath: src), !fm.fileExists(atPath: dst) {
                    try? fm.copyItem(atPath: src, toPath: dst)
                }
            }
        }
        return newURL
    }
}

@main
struct OpenSourceShelfApp: App {
    let container: ModelContainer
    @StateObject private var appRefreshStore = AppRefreshStore()
    @StateObject private var catalogStateStore = CatalogIntelligenceStateStore()
    @StateObject private var queueViewModel = QueueViewModel()
    @StateObject private var queueMenuState = QueueMenuPresentationState()
    @StateObject private var runbookWindowState = RunbookWindowState()
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @AppStorage(LabsFeatures.storageKey) private var labsFeaturesEnabled = false

    init() {
        // Carry over data from the previous "OpenSourceShelf" name. Must run
        // before any DB/UserDefaults access below.
        LegacyNameMigration.runIfNeeded()

        #if DEBUG
        Self.runDebugCommandIfRequested()
        #endif

        do {
            try IntelligenceDatabase.shared.initialize()
            #if DEBUG
            print("[reshelf] Intelligence database initialized at \(IntelligenceDatabase.shared.databaseURL.path)")
            #endif
        } catch {
            #if DEBUG
            print("[reshelf] Intelligence database initialization failed: \(error)")
            #endif
        }

        do {
            let schema = Schema([ToolProject.self, AppSettings.self])
            // Use an app-specific store under ~/reshelf instead of the shared,
            // non-namespaced ~/Library/Application Support/default.store. The shared
            // store is dangerous for a non-sandboxed app: any other SwiftData app or
            // a schema-divergent build that opens it can trigger a destructive reset.
            let storeURL = CatalogStoreLocation.migrateAndResolve()
            let config = ModelConfiguration(schema: schema, url: storeURL)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(catalogStateStore: catalogStateStore)
                .environmentObject(appRefreshStore)
                .environmentObject(runbookWindowState)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About reshelf") {
                    Self.showAboutPanel()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Project…") {
                    NotificationCenter.default.post(name: .addProject, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Quick Capture…") {
                    NotificationCenter.default.post(name: .quickCapture, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Search…") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Export Catalog as JSON…") {
                    NotificationCenter.default.post(name: .exportCatalog, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import GitHub URLs…") {
                    NotificationCenter.default.post(name: .importURLs, object: nil)
                }

                Button("Restore from Backup…") {
                    NotificationCenter.default.post(name: .restoreBackup, object: nil)
                }
            }

            // One View menu: column toggles live in the standard sidebar slot,
            // navigation is appended right after so there is no duplicate "View".
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebarColumn, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleInspectorColumn, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Divider()

                Menu("Project List") {
                    sidebarMenuButton(.allProjects)
                    sidebarMenuButton(.topShelf)
                    sidebarMenuButton(.collector)
                    sidebarMenuButton(.yardSale)
                }

                Menu("Categories") {
                    ForEach(SidebarItem.sidebarCategoryItems) { item in
                        sidebarMenuButton(item)
                    }
                }

                if labsFeaturesEnabled {
                    Divider()

                    sidebarMenuButton(.compare)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    sidebarMenuButton(.ecosystems)
                    sidebarMenuButton(.workflows)
                    sidebarMenuButton(.myStack)
                }
            }

            // Catalog (intelligence) + Actions menus are the v2 Intelligence
            // surface — shown only when Labs is enabled.
            if labsFeaturesEnabled {
            CommandMenu("Catalog") {
                Menu("Runbook Filter") {
                    ForEach(CatalogRunbookFilter.allCases) { filter in
                        Button(filter.rawValue) {
                            NotificationCenter.default.post(
                                name: .setCatalogRunbookFilter,
                                object: nil,
                                userInfo: ["filter": filter.rawValue]
                            )
                        }
                    }
                }

                Divider()

                Button("Fetch Intelligence for Visible List") {
                    NotificationCenter.default.post(name: .catalogFetchAllIntelligence, object: nil)
                }

                if labsFeaturesEnabled {
                    Divider()

                    Button("Select Projects to Compare") {
                        NotificationCenter.default.post(name: .toggleCatalogCompareMode, object: nil)
                    }

                    Button("Compare Checked Projects") {
                        NotificationCenter.default.post(name: .catalogCompareSelected, object: nil)
                    }
                    .keyboardShortcut("c", modifiers: [.command, .option])

                    Button("Cancel Compare Selection") {
                        NotificationCenter.default.post(name: .catalogCancelCompareMode, object: nil)
                    }
                }
            }

            CommandMenu("Actions") {
                Button("Generate Runbook") {
                    AppQuickActionCenter.post(.generateRunbook)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Open Runbook") {
                    AppQuickActionCenter.post(.openRunbook)
                }

                Button("Regenerate Stale Runbooks") {
                    AppQuickActionCenter.post(.regenerateStaleRunbooks)
                }

                Divider()

                Button("Show Needs Runbook") {
                    AppQuickActionCenter.post(.showNeedsRunbook)
                }

                Button("Show Stale Runbooks") {
                    AppQuickActionCenter.post(.showStaleRunbooks)
                }

                if labsFeaturesEnabled {
                    Divider()

                    Button("Compare Current Project") {
                        AppQuickActionCenter.post(.compareSelected)
                    }
                }

                Divider()

                Button("Refresh Intelligence") {
                    AppQuickActionCenter.post(.refreshIntelligence)
                }
            }
            } // labsFeaturesEnabled — Catalog + Actions menus

            // Queue + Explore are v2 surfaces — only in the Window menu under Labs.
            CommandGroup(after: .windowList) {
                if labsFeaturesEnabled {
                    Button("Show Queue") {
                        queueMenuState.present()
                    }
                    .keyboardShortcut("q", modifiers: [.command, .shift])

                    Menu("Explore") {
                        sidebarMenuButton(.ecosystems)
                        sidebarMenuButton(.workflows)
                        sidebarMenuButton(.myStack)
                    }
                }
            }
        }

        Window("Queue", id: ShelfWindowID.queue) {
            QueueMenuBarRoot(viewModel: queueViewModel)
                .environmentObject(appRefreshStore)
                .frame(minWidth: 400, idealWidth: 440, minHeight: 480, idealHeight: 560)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 560)

        Window("Runbook", id: ShelfWindowID.runbook) {
            RunbookWindowView()
                .environmentObject(runbookWindowState)
                .environmentObject(appRefreshStore)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 640)

        // Standard macOS Settings — app-menu "Settings…" (⌘,). Opens at a sensible
        // size and is freely resizable: a min floor + ideal opening size, no max, with
        // .contentMinSize so the user can drag it larger/smaller and the size is
        // remembered. Tab content scrolls within whatever size is chosen.
        Settings {
            SettingsView()
                .frame(minWidth: 480, idealWidth: 580, maxWidth: .infinity,
                       minHeight: 360, idealHeight: 560, maxHeight: .infinity)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .windowResizability(.contentMinSize)
        .modelContainer(container)
    }

    /// Native About panel — shows the app icon, name, and version automatically,
    /// plus a short reshelf credits line. Used in place of the default `.appInfo`
    /// item so we control the tagline without maintaining a separate window.
    private static func showAboutPanel() {
        let credits = NSAttributedString(
            string: "A local-first shelf for the open-source tools you want to remember.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "reshelf"
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func sidebarMenuButton(_ item: SidebarItem) -> some View {
        Button(item.title) {
            NotificationCenter.default.post(
                name: .selectSidebarItem,
                object: nil,
                userInfo: ["item": item.rawValue]
            )
        }
    }
}

#if DEBUG
private extension OpenSourceShelfApp {
    static func runDebugCommandIfRequested() {
        guard CommandLine.arguments.contains("--oss-db-smoke") else {
            return
        }

        do {
            let database = IntelligenceDatabase.shared
            try database.smokeTest()
            print(try database.debugSchemaSummary())
            exit(EXIT_SUCCESS)
        } catch {
            print("[reshelf] Database smoke failed: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }
}
#endif

/// App-wide appearance preference, stored in `@AppStorage` and applied via
/// `.preferredColorScheme` on every scene root.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearanceMode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` follows the system setting; otherwise forces light or dark.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Notification.Name {
    static let addProject = Notification.Name("addProject")
    static let quickCapture = Notification.Name("quickCapture")
    static let openQueue = Notification.Name("openQueue")
    static let openCommandPalette = Notification.Name("openCommandPalette")
    static let toggleSidebarColumn = Notification.Name("toggleSidebarColumn")
    static let toggleInspectorColumn = Notification.Name("toggleInspectorColumn")
    static let exportCatalog = Notification.Name("exportCatalog")
    static let importURLs = Notification.Name("importURLs")
    static let restoreBackup = Notification.Name("restoreBackup")
}
