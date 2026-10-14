import SwiftUI
import SwiftData
import AppKit
import Darwin
import SQLite3

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
           let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           isReshelfStore(appSupport.appendingPathComponent("default.store").path) {
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

    /// The shared default.store can belong to any other non-sandboxed SwiftData
    /// app; only adopt it when it holds reshelf's own table.
    private static func isReshelfStore(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ZTOOLPROJECT'"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Set when the catalog file couldn't be opened and was moved aside; shown
    /// once the app has launched.
    static var recoveryNotice: String?

    /// The store couldn't be opened (corrupt file, or a store from a newer
    /// reshelf). Instead of crashing at every launch, move it and its sidecars
    /// aside — kept, never deleted — so a fresh store opens and the usual
    /// "catalog is empty" auto-restore brings the newest backup back.
    static func moveAside(_ storeURL: URL, error: Error) {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: Date())
        let keptBase = storeURL.deletingLastPathComponent()
            .appendingPathComponent("catalog-unreadable-\(stamp).store").path
        for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: storeURL.path + suffix) {
            try? fm.moveItem(atPath: storeURL.path + suffix, toPath: keptBase + suffix)
        }
        recoveryNotice = """
        reshelf couldn't open its catalog file, so it started a new one and restored your newest backup into it.

        The old file is kept at \(keptBase). If you had just used a newer reshelf, quit, update and move that file back to catalog.store.

        Error: \(error.localizedDescription)
        """
    }
}

/// SwiftUI's `CommandGroup(replacing: .textFormatting) {}` empties the Format
/// menu but leaves the empty menu itself in the menu bar. Prune it at the AppKit
/// level — and keep pruning, because SwiftUI rebuilds the main menu whenever the
/// `commands` re-evaluate.
final class FormatMenuPruner: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.prune()
        if let notice = CatalogStoreLocation.recoveryNotice {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Catalog restored from backup"
                alert.informativeText = notice
                alert.runModal()
            }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.prune()
        }
    }

    private static func prune() {
        guard let menu = NSApp.mainMenu,
              let format = menu.items.first(where: { $0.title == "Format" }) else { return }
        menu.removeItem(format)
    }
}

@main
struct OpenSourceShelfApp: App {
    @NSApplicationDelegateAdaptor(FormatMenuPruner.self) private var formatMenuPruner
    let container: ModelContainer
    @StateObject private var appRefreshStore = AppRefreshStore()
    @StateObject private var updaterService = UpdaterService.shared
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system

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
            let schema = Schema([ToolProject.self, AppSettings.self, CatalogFolder.self])
            // Use an app-specific store under ~/reshelf instead of the shared,
            // non-namespaced ~/Library/Application Support/default.store. The shared
            // store is dangerous for a non-sandboxed app: any other SwiftData app or
            // a schema-divergent build that opens it can trigger a destructive reset.
            let storeURL = CatalogStoreLocation.migrateAndResolve()
            let config = ModelConfiguration(schema: schema, url: storeURL)
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                CatalogStoreLocation.moveAside(storeURL, error: error)
                container = try ModelContainer(for: schema, configurations: config)
            }
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appRefreshStore)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .modelContainer(container)
        .handlesExternalEvents(matching: ["*"])
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About reshelf") {
                    Self.showAboutPanel()
                }
                Button("Check for Updates…") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.canCheckForUpdates)
            }

            CommandGroup(replacing: .newItem) {
                // The manual "New Project" form was removed in 1.14.0: Quick
                // Capture fills everything from GitHub, so it owns ⌘N now.
                Button("Quick Capture…") {
                    NotificationCenter.default.post(name: .quickCapture, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Search…") {
                    NotificationCenter.default.post(name: .openCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Export Catalog as JSON…") {
                    NotificationCenter.default.post(name: .exportCatalog, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Import Catalog from JSON…") {
                    NotificationCenter.default.post(name: .importCatalog, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Import GitHub URLs…") {
                    NotificationCenter.default.post(name: .importURLs, object: nil)
                }

                Button("Restore from Backup…") {
                    NotificationCenter.default.post(name: .restoreBackup, object: nil)
                }

                Divider()

                Button("Check Clones for Updates") {
                    NotificationCenter.default.post(name: .checkCloneUpdates, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Pull Clones with Updates") {
                    NotificationCenter.default.post(name: .pullCloneUpdates, object: nil)
                }
                .keyboardShortcut("u", modifiers: .command)

                Button("Remove Duplicate Repos…") {
                    NotificationCenter.default.post(name: .removeDuplicateRepos, object: nil)
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

            }

            // Drop the default Format menu (Show Fonts steals ⌘T) — this app has
            // no rich-text formatting, and ⌘T is our "Move to Top Shelf".
            CommandGroup(replacing: .textFormatting) { }

            // Quick shelf moves for the selected repo (no mouse needed).
            CommandMenu("Shelf") {
                Button("Move to Top Shelf") {
                    NotificationCenter.default.post(name: .moveSelectedToShelf, object: ProjectStatus.topShelf.rawValue)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Move to The Collector") {
                    NotificationCenter.default.post(name: .moveSelectedToShelf, object: ProjectStatus.collector.rawValue)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Move to Yard Sale") {
                    NotificationCenter.default.post(name: .moveSelectedToShelf, object: ProjectStatus.yardSale.rawValue)
                }
                .keyboardShortcut("y", modifiers: .command)

                Divider()

                Button("Move Repos Without a License to Yard Sale…") {
                    NotificationCenter.default.post(name: .yardSaleUnlicensed, object: nil)
                }

                Divider()

                // Not-cloned repos only; clones refresh when they are pulled.
                Button("Refresh Info for Top Shelf") {
                    NotificationCenter.default.post(name: .refreshRepoInfo, object: ProjectStatus.topShelf.rawValue)
                }
                Button("Refresh Info for The Collector") {
                    NotificationCenter.default.post(name: .refreshRepoInfo, object: ProjectStatus.collector.rawValue)
                }
            }

        }

        // Standard macOS Settings — app-menu "Settings…" (⌘,).
        //
        // One fixed size for every tab (Kika's spec: 560pt wide, no resizing
        // per tab). A fixed frame with .contentSize also overrides an old saved
        // window size. Tabs taller than this (Guide) scroll.
        Settings {
            SettingsView()
                .frame(width: 560, height: 620)
                .preferredColorScheme(appearanceMode.colorScheme)
        }
        .windowResizability(.contentSize)
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
            try database.initialize()
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
    static let quickCapture = Notification.Name("quickCapture")
    static let openCommandPalette = Notification.Name("openCommandPalette")
    /// Sidebar navigation from the app's View menu (userInfo["item"]: SidebarItem rawValue).
    static let selectSidebarItem = Notification.Name("selectSidebarItem")
    /// Filter the list to one tag, e.g. from an inspector tag chip (object: `SidebarTagRanking.key`).
    static let selectSidebarTag = Notification.Name("selectSidebarTag")
    static let toggleSidebarColumn = Notification.Name("toggleSidebarColumn")
    static let toggleInspectorColumn = Notification.Name("toggleInspectorColumn")
    /// Scroll the project list to a row (object: the project's UUID).
    static let revealProjectInList = Notification.Name("revealProjectInList")
    static let exportCatalog = Notification.Name("exportCatalog")
    static let importURLs = Notification.Name("importURLs")
    static let importCatalog = Notification.Name("importCatalog")
    static let restoreBackup = Notification.Name("restoreBackup")
    static let checkCloneUpdates = Notification.Name("checkCloneUpdates")
    static let pullCloneUpdates = Notification.Name("pullCloneUpdates")
    /// Check + pull the cloned repos in one folder (object: the folder's UUID).
    static let pullFolderClones = Notification.Name("pullFolderClones")
    /// Move the currently selected repo to a shelf; object is the ProjectStatus rawValue.
    static let moveSelectedToShelf = Notification.Name("moveSelectedToShelf")
    /// A clone's update status became known (object: project id string, userInfo["behind"]: Bool)
    /// — lets the list's "updates available" row dot stay in sync after a pull/check.
    static let cloneUpdateStatusKnown = Notification.Name("cloneUpdateStatusKnown")
    static let removeDuplicateRepos = Notification.Name("removeDuplicateRepos")
    static let yardSaleUnlicensed = Notification.Name("yardSaleUnlicensed")
    static let refreshRepoInfo = Notification.Name("refreshRepoInfo")
}
