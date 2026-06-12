# AGENTS.md — reshelf

Instructions for **coding agents** (and humans) working in this repo — **project-specific** rules. If you have machine-wide agent preferences, they layer on top.

## What this app is

**reshelf** (display name; Xcode project/module folder `OpenSourceShelf`) — a local-first macOS SwiftUI app to catalog open-source repos: capture from GitHub, organize onto shelves, auto-categorize, and clone locally by category.

**Two layers, one flag:**
- **v1 — the Catalog** (default, always on): capture, shelves (Top Shelf / The Collector / Yard Sale), categories, cloning + update checks, license explainer, duplicate protection, backups. Zero setup, no AI.
- **v2 — the Intelligence engine** (clone + AI analysis, runbooks, Compare, Ecosystems): **dormant behind `LabsFeatures`** (`Settings → Enable Intelligence`, off by default). The code is preserved, not deleted — gate any new intelligence surface behind `labsFeaturesEnabled`; never wire it into the v1 default path. Runbooks are generate/copy/export only — **never executed in-app**.

## Architecture (do not guess)

- **UI catalog:** `ToolProject`, `AppSettings` — **SwiftData** (`OpenSourceShelfApp` model container).
- **Intelligence layer:** `RepositoryRecord`, metadata, clone/queue/graph/recommendation/ecosystem tables — **GRDB** via `IntelligenceDatabase` at `~/reshelf/database/opensource-shelf.sqlite` (currently through migration `v10_graph_search_cache`).
- **Cloning (v1):** `Services/CatalogCloneService.swift` is the AI-free clone path used by the catalog. Full clones land under `CloneLocation.rootURL` (default `~/reshelf/repos`, overridable via the **Repository Storage** setting `reshelf.cloneRootPath`) grouped by category: `<root>/<Category>/<repo>` (fallback `<owner>-<repo>` on a name collision). LFS smudge/clean filters are bypassed so LFS repos clone without `git-lfs`. `isCloned`/`existingClone` use a **cached index** (`owner/repo` → path) so per-row lookups stay O(1) — call `invalidateCloneIndex()` after a clone or move; a stale hit (user deleted the folder in Finder) self-heals with one rescan. `removeClone()` moves a checkout to the **Trash** (never hard-deletes) and tidies an emptied category folder; it backs the row context menu's "Remove Local Clone…". Update checks are a read-only `git ls-remote` (no fetch). Not sandboxed → plain paths. The v2 intelligence engine has its *own* clone path (`RepositoryCloneService`, `<host>/<owner>/<name>/worktree`) — don't confuse the two.
- **Retrieval:** deterministic graph/recommendation/ecosystem ranking stays primary. Relationship data lives in GRDB (`graph_nodes` / `graph_edges`) and surfaces in Inspect/Compare — there is **no Graph sidebar/canvas** in the UI.
- **SwiftData vs GRDB:** `ToolProject` remains the catalog capture layer. Intelligence surfaces (Queue, Ecosystems/Workflows/My Stack, Inspect metadata) read GRDB; extend GRDB + services before duplicating fields in SwiftData unless there is an explicit sync plan.
- **Catalog ↔ intelligence bridge:** `IntelligenceRepositoryBridge.findIntelligenceRepository(for:)` matches GitHub URL → normalized URL → owner/name → unique name fallback. Derived row state lives in `CatalogIntelligenceState` / `CatalogIntelligenceStateStore` (batched GRDB reads, 2s poll fallback).
- **Refresh bus:** `Services/AppRefresh/` — `AppRefreshBus` emits typed `AppRefreshEvent`s; `AppRefreshStore` (@MainActor) debounces catalog refresh and drives cross-surface updates (catalog badges, detail runbook, queue, compare). Prefer emitting bus events from services over ad-hoc `NotificationCenter` posts.
- **Menu bar (`OpenSourceShelfApp.commands`):** **File** (New / Quick Capture / Search / Export / Import / Restore / **Check Clones for Updates** ⌘⇧U / **Remove Duplicate Repos**), a **Shelf** menu (⌘T / ⌘Y / ⌘⇧G move the selected repo), the **View** menu (column toggles in the standard `.sidebar` slot + a **Project List** / **Categories** navigation group via `CommandGroup(after: .sidebar)` — do **not** add a second `CommandMenu("View")`), and the app menu (Settings, About). The intelligence menus — **Catalog**, **Actions**, and **Window → Queue** — are wrapped in `if labsFeaturesEnabled` and only appear under Labs. The **sidebar** lists catalog filters only (**Library** incl. shelves + Cloned, and the dynamic **Categories**). There is **no menu bar extra / status item**. Cross-surface actions go through typed `Notification.Name`s and the refresh bus; the catalog-heavy notification handlers in `ProjectListView` are bundled into a `CatalogEventHandlers` `ViewModifier` to keep `body` type-checkable.
- **Settings:** a SwiftUI **`Settings` scene** in `OpenSourceShelfApp` — opens from the app menu (**reshelf → Settings…**, ⌘,) as a standalone pop-up window. The scene gets its own `.modelContainer(container)` so `SettingsView` has a SwiftData context. There is **no in-app settings panel** anymore (the old `showsSettingsPanel` detail-column path and the sidebar Settings button were removed) — don't re-add one.
- **Appearance / dark mode:** `AppearanceMode` enum (System/Light/Dark) stored in `@AppStorage(AppearanceMode.storageKey)` — **not** in SwiftData `AppSettings`, because it must apply at scene level. Each scene root (`ContentView`, Queue window, `SettingsView`) gets `.preferredColorScheme(appearanceMode.colorScheme)` (`.system` → `nil`). The picker is the Appearance section in `SettingsView`. Dark mode relies on semantic colors only (`Color(nsColor:.windowBackgroundColor/.controlBackgroundColor)`, `.primary`/`.secondary`/`.tertiary`, system accent colors) — **do not introduce hardcoded `Color.white`/`.black`/RGB**, or it will break one appearance.
- **Command palette:** `CommandPaletteView` (⌘K) — sheet with search, recent searches (JSON-encoded in `@AppStorage`), project filtering, GitHub URL detection. URL capture uses `QuickCaptureRequest` (Identifiable item-based `.sheet`) so the URL survives the palette→capture sheet transition. Escape dismissal via `NSEvent.addLocalMonitorForEvents`.
- **Window chrome (merged title-bar row):** there is **no `.toolbar` content** — the title-bar band is the column-header row itself (Claude/Cursor-style). `NavigationSplitView`'s automatic sidebar toggle is removed via `.toolbar(removing: .sidebarToggle)` on `sidebarColumn` (this **does** work on macOS 14+; the old note that it didn't was wrong). The chrome controls now live **inside the project-list header** (`ProjectListView`) as `HeaderChromeButton`s: a leading **sidebar toggle**, and trailing **search** + **inspector toggle**. They post the existing `.toggleSidebarColumn` / `.openCommandPalette` / `.toggleInspectorColumn` notifications (no new plumbing), and they sit in the always-present list header so they stay reachable when the sidebar or inspector is collapsed. The brand (owl) header is the sidebar column's `AlignedSplitColumnHeader`. ⌘S / ⌘K / ⌘I menu shortcuts still drive the same notifications. Do **not** re-add `.toolbar` items or a second sidebar toggle — that reintroduces the empty title-bar band.
- **Category classification:** `Services/CategoryClassifier.swift` maps GitHub topics + description + repo name to a meaningful category (Database, AI / Agent, macOS, Workspace, Internal Tools, Backend, Knowledge, CLI, DevOps, Media, Design, Automation, Security, Utility, Editor) via **weighted scoring**, not first-match: strong topics (4) > strong description phrases (3) > weak topics / name tokens (2) > weak phrases (1); highest total ≥ 2 wins, ties go to the earlier rule. All matching is **word/token-boundary** (topics split on hyphens, descriptions normalized to space-separated words) — never raw `contains`, which produced "storage"→"rag"→AI / Agent-type misfires. The language fallback (Swift→macOS, Python+AI words→AI / Agent) only runs when nothing scores. `classify()` runs in Quick Capture; `reclassify()` + `isMeaningfulCategory()` retro-fix existing rows via `ContentView.reclassifyProjectsIfNeeded()` on appear (meaningful categories are kept, so manual fixes survive). These categories are what the sidebar filter predicates (`SidebarItem`) match against — keep the two in sync.
- **Inspector sections:** `InspectorSection` enum (in `AppSettings.swift`) drives both visibility and order. Order persists as a JSON string in `AppSettings.inspectorSectionOrder` (new enum cases auto-append). Settings shows a drag-reorderable list (`InspectorSectionRow`, `.draggable`/`.dropDestination`); `InspectView` renders via `inspectorSectionContent(_:)` in that order. The deep-intelligence blocks (intelligence/compare/runbook) stay fixed and are **not** reorderable.
- **Resizable panels:** Sidebar resizes natively via `navigationSplitViewColumnWidth` bounds (the `NSSplitViewDelegate` lock was removed). The inspector resizes via a custom AppKit `ResizeDivider` writing `inspectorWidth` (@AppStorage). `ResizeDivider` must track **window** coordinates, not the divider's local space — see the UI rules note below.

## Safety boundary (never build without explicit ask)

- Do **not** run shell commands, Docker, package managers, or repo mutation from the app.
- Runbook UI wording: **Generate**, **Copy**, **Export**, **Open**, **Refresh** — not Run/Execute/Install.
- No MCP server mode, autonomous agents, or install automation in core paths.

## UI rules (from user preferences)

- **Mac-native polish** — unified window chrome (`.windowToolbarStyle(.unified)`), full-height sidebar flush with content; avoid floating disconnected panels.
- **Main window title** — hide the redundant app title with `MainWindowChromeConfigurator` plus empty `.navigationTitle("")`. The configurator also **flattens the sidebar split divider**: it walks the `NSSplitView` backing `NavigationSplitView`, sets `dividerStyle = .thin`, and clears the drop shadow on the split view + its arranged subviews so the sidebar edge is a clean 1px hairline (matching the inspector's `ResizeDivider`) instead of the heavy "Finder" shadow. It retries over a few frames (the split view appears late) and is re-applied after each sidebar toggle (`toggleSidebarColumn`) and on appearance flips. **Two macOS 26/27 gotchas baked into it:** (1) configuration hangs off `viewDidMoveToWindow` in a custom NSView — `updateNSView` is never re-called once the view has a window there, so an updateNSView-based configurator silently does nothing; (2) the Liquid-Glass title-bar backdrops (`NSTitlebarBackgroundView` hosting `NSScrollPocket`, direct subviews of the NSSplitView — not NSVisualEffectViews) paint a gray/dimming band over the header row. They're created lazily and re-shown by AppKit, so `hideTitlebarBackdrops` re-asserts on every `NSWindow.didUpdateNotification` (cheap: direct split-view children only) plus a KVO guard per view. On macOS 26+ the NSSplitView divider also renders **zero-width**, so the visible sidebar/list line is a 1px `separatorColor` overlay on `SidebarView`'s trailing edge (same color the inspector's `ResizeDivider` draws).
- **Resizable side panels** — sidebar and inspector are both **user-resizable** (the project list column flexes between them). Sidebar uses native `navigationSplitViewColumnWidth(min:ideal:max:)` bounds (the old `NSSplitViewDelegate` width lock in `MainWindowChromeConfigurator` was removed). Inspector is a fixed-frame `HStack` child whose width (`inspectorWidth`, @AppStorage) is driven by the AppKit `ResizeDivider`. **Resize-divider gotcha:** track the cursor in **window coordinates** anchored at mouse-down, not the divider's local space — the divider slides as the panel resizes, so local-space deltas collapse to ~0 and the resize jitters. Don't "fix" jitter with a blur mask; fix the coordinate math. If exact sidebar parity is wanted, switch the detail+inspector pair to `HSplitView`.
- **Split column dividers** — align sidebar, middle, and detail header dividers with `AlignedSplitColumnHeader` (**38pt** fixed height in `ShelfLayout.swift`). Queue, Ecosystems, Workflows, and My Stack use the same header pattern. **Alignment is by construction, not by nudge:** the sidebar root (`SidebarView`) and the detail `HStack` (`ContentView.catalogDetailHStack`) both apply `.ignoresSafeArea(.container, edges: .top)` so every column lays out from the window's top edge — header at 0–38, divider at 38, one continuous line. Do **not** reintroduce measured nudge constants (the old `headerTopAlignmentNudge` −10 broke when macOS 26/27 changed the per-column top insets). Because the header row sits at the window top, content at the window's top-left needs `leadingInset: ShelfLayout.trafficLightHeaderInset` to clear the traffic lights — the sidebar brand header always, the project-list header only while the sidebar is collapsed (`needsTrafficLightInset`).
- **Quick Capture** — after save, clear the project URL/search field for the next repo; place AI suggestions at the top with Generate → Generated / Re-generate; keep Quick Flags for filtering (AI may auto-check when obvious).
- **Title-bar chrome** — the column-header row **is** the title bar (no `.toolbar` items; the system sidebar toggle is removed via `.toolbar(removing: .sidebarToggle)`). Sidebar toggle (leading) + search + inspector toggle (trailing) are `HeaderChromeButton`s in the **project-list header**, posting notifications. Keep the brand (owl) header in the sidebar's `AlignedSplitColumnHeader`; the brand glyph comes from the **app icon** (`ReshelfBrandImage` → `NSImage.applicationIconName`, falling back to bundled `ReshelfBrand.png`) so it always matches AppIcon. Don't reintroduce `.toolbar` items or a second sidebar toggle.
- **Do not use** SwiftUI `.inspector()` on split-view detail — it adds a fourth column; embed extra metadata **inside** the detail pane.
- **Stabilize the main window** (hierarchy, empty states, list/detail) **before** command palette, menu bar extra, or other peripheral capture flows.
- **Floating capture** (Quick Capture sheet, future palette): prefer **solid opaque** surfaces, not heavy glass, so text stays readable over bright windows.
- **Optional chrome** (inspector sections, metadata blocks): should be **hideable via Settings**, not always on.
- **No login / sign-in** — frictionless local tool unless the user explicitly asks otherwise.

## Docs rules

- Project docs use **plain language**; explain jargon inline (SwiftData = Apple’s on-disk model store, GRDB = SQLite toolkit, etc.).
- Track near-term work in [todo.md](todo.md); record shipped changes in [CHANGELOG.md](CHANGELOG.md).
- When adding user-facing docs, keep [README.md](README.md) as entry point with **“In one minute”** and **“How you run it”** before deep detail.
- Keep [features.md](features.md), [goals.md](goals.md), [future-features.md](future-features.md), and [todo.md](todo.md) in sync when behavior changes.

## Build and verify

```bash
xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" -destination 'platform=macOS' build
```

- Scheme name: **OpenSource Shelf** (the Xcode target/scheme/module keep the legacy name). The shipping product is **reshelf**: `PRODUCT_NAME = "reshelf"` (built bundle `reshelf.app`, `CFBundleName = reshelf`) and `CFBundleDisplayName = reshelf`. The **bundle ID stays `com.kika.opensourceshelf`** (changing it would relocate the SwiftData catalog + reset permissions). `build.sh` builds `-scheme "OpenSource Shelf"` but copies `reshelf.app`.
- **Name migration:** `LegacyNameMigration` (in `OpenSourceShelfApp.swift`, runs first in `init()`) moves `~/OpenSourceShelf` → `~/reshelf` and renames `OpenSourceShelf.*` UserDefaults keys → `reshelf.*` (same domain, since bundle ID is unchanged). The SQLite filename stays `opensource-shelf.sqlite` (invisible).
- SPM dependency: **GRDB** — first build may fetch packages.
- This workspace is a git repository on branch `main`.
- Ignore `.build/` in git; do not commit DerivedData or package checkouts.

## AI integrations

- **Ollama** — settings in `AppSettings`; `OllamaService` for `/api/tags` and Quick Capture AI prompts.
- **Apple Intelligence** — toggle exists; wire or hide until real Foundation Models integration exists.
- Prefer **local-first**; no new cloud-only dependencies without user approval.

## Code style

- Match existing Swift files: small views, `@Model` for catalog, GRDB `FetchableRecord` for intelligence tables.
- **Minimal diffs** — do not refactor unrelated code in the same change.
- Comments only for non-obvious behavior (migrations, sync boundaries, GitHub rate limits).

## Commits

- Only commit when the maintainer/user asks.
- No force-push to `main`/`master`.
