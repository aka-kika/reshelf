# AGENTS.md — reshelf

Instructions for **coding agents** (and you) working in this repo. User-wide preferences live in `/Users/kika_hub/AGENTS.md`; this file adds **project-specific** rules.

## What this app is

**reshelf** (display name; repo folder `OpenSourceShelf`) — macOS SwiftUI app to catalog open-source tools for *your* workflows (Codex, local AI, macOS apps, private projects, content/design). Capture-first UX is a goal; the **main window** (sidebar + list + detail) is the current focus.

**Current stage:** Intelligence engine + catalog runbook sync + shared refresh bus (Stage 21). Runbooks are generate/copy/export only — never executed in-app. Sidebar/inspector layout, command palette, **auto-categorized capture**, and a **show/hide + drag-reorder inspector** are complete; both side panels are now **user-resizable**. See `.handoff/quick-re-entry.md` for handoff context.

## Architecture (do not guess)

- **UI catalog:** `ToolProject`, `AppSettings` — **SwiftData** (`OpenSourceShelfApp` model container).
- **Intelligence layer:** `RepositoryRecord`, metadata, clone/queue/graph/recommendation/ecosystem tables — **GRDB** via `IntelligenceDatabase` at `~/reshelf/database/opensource-shelf.sqlite` (currently through migration `v10_graph_search_cache`).
- **Clone location:** repos are cloned under `CloneLocation.rootURL` (in `RepositoryCloneService.swift`), which reads the user's chosen folder from `UserDefaults` (`reshelf.cloneRootPath`, surfaced as the **Repository Storage** picker in Settings) and falls back to `~/reshelf/repos`. `cloneOrFetch(cloneRootURL:)` defaults to it, so callers pass `nil`. Repos are namespaced `<root>/<host>/<owner>/<name>/worktree`. Not sandboxed → a plain path (no security-scoped bookmark). Changing the folder affects only **new** clones.
- **Retrieval:** deterministic graph/recommendation/ecosystem ranking stays primary. Relationship data lives in GRDB (`graph_nodes` / `graph_edges`) and surfaces in Inspect/Compare — there is **no Graph sidebar/canvas** in the UI.
- **SwiftData vs GRDB:** `ToolProject` remains the catalog capture layer. Intelligence surfaces (Queue, Ecosystems/Workflows/My Stack, Inspect metadata) read GRDB; extend GRDB + services before duplicating fields in SwiftData unless there is an explicit sync plan.
- **Catalog ↔ intelligence bridge:** `IntelligenceRepositoryBridge.findIntelligenceRepository(for:)` matches GitHub URL → normalized URL → owner/name → unique name fallback. Derived row state lives in `CatalogIntelligenceState` / `CatalogIntelligenceStateStore` (batched GRDB reads, 2s poll fallback).
- **Refresh bus:** `Services/AppRefresh/` — `AppRefreshBus` emits typed `AppRefreshEvent`s; `AppRefreshStore` (@MainActor) debounces catalog refresh and drives cross-surface updates (catalog badges, detail runbook, queue, compare). Prefer emitting bus events from services over ad-hoc `NotificationCenter` posts.
- **Menu bar (`OpenSourceShelfApp.commands`):** one **View** menu (column toggles in the standard `.sidebar` slot + **Library** / **My Workflows** submenus + Compare/Ecosystems/Workflows/My Stack navigation via `CommandGroup(after: .sidebar)` — do **not** add a second `CommandMenu("View")`), **Catalog** (runbook filter, fetch intelligence, multi-select compare flow), **Actions** (runbook generate/open + intelligence). "Show Queue" (⌘⇧Q) and **Explore** (Ecosystems/Workflows/My Stack) live in the **Window** menu via `CommandGroup(after: .windowList)`. The **sidebar** lists catalog filters only (**Library**, **Categories**, **My Workflows**) — not Compare or discovery modes. There is **no menu bar extra / status item** and **no Navigate menu** — both were removed as redundant. `AppQuickAction` (posted from the Actions menu) routes to `ContentView` / catalog handlers; sidebar navigation uses `.selectSidebarItem`.
- **Settings:** a SwiftUI **`Settings` scene** in `OpenSourceShelfApp` — opens from the app menu (**reshelf → Settings…**, ⌘,) as a standalone pop-up window. The scene gets its own `.modelContainer(container)` so `SettingsView` has a SwiftData context. There is **no in-app settings panel** anymore (the old `showsSettingsPanel` detail-column path and the sidebar Settings button were removed) — don't re-add one.
- **Appearance / dark mode:** `AppearanceMode` enum (System/Light/Dark) stored in `@AppStorage(AppearanceMode.storageKey)` — **not** in SwiftData `AppSettings`, because it must apply at scene level. Each scene root (`ContentView`, Queue window, `SettingsView`) gets `.preferredColorScheme(appearanceMode.colorScheme)` (`.system` → `nil`). The picker is the Appearance section in `SettingsView`. Dark mode relies on semantic colors only (`Color(nsColor:.windowBackgroundColor/.controlBackgroundColor)`, `.primary`/`.secondary`/`.tertiary`, system accent colors) — **do not introduce hardcoded `Color.white`/`.black`/RGB**, or it will break one appearance.
- **Command palette:** `CommandPaletteView` (⌘K) — sheet with search, recent searches (JSON-encoded in `@AppStorage`), project filtering, GitHub URL detection. URL capture uses `QuickCaptureRequest` (Identifiable item-based `.sheet`) so the URL survives the palette→capture sheet transition. Escape dismissal via `NSEvent.addLocalMonitorForEvents`.
- **Window chrome (merged title-bar row):** there is **no `.toolbar` content** — the title-bar band is the column-header row itself (Claude/Cursor-style). `NavigationSplitView`'s automatic sidebar toggle is removed via `.toolbar(removing: .sidebarToggle)` on `sidebarColumn` (this **does** work on macOS 14+; the old note that it didn't was wrong). The chrome controls now live **inside the project-list header** (`ProjectListView`) as `HeaderChromeButton`s: a leading **sidebar toggle**, and trailing **search** + **inspector toggle**. They post the existing `.toggleSidebarColumn` / `.openCommandPalette` / `.toggleInspectorColumn` notifications (no new plumbing), and they sit in the always-present list header so they stay reachable when the sidebar or inspector is collapsed. The brand (owl) header is the sidebar column's `AlignedSplitColumnHeader`. ⌘S / ⌘K / ⌘I menu shortcuts still drive the same notifications. Do **not** re-add `.toolbar` items or a second sidebar toggle — that reintroduces the empty title-bar band.
- **Category classification:** `Services/CategoryClassifier.swift` maps GitHub topics → description → language to a meaningful category (Database, AI / Agent, macOS, Workspace, Backend, Knowledge, CLI, DevOps, Media, Design, Automation, Security, Utility, Editor). `classify()` runs in Quick Capture; `reclassify()` + `isMeaningfulCategory()` retro-fix existing rows via `ContentView.reclassifyProjectsIfNeeded()` on appear. These categories are what the sidebar filter predicates (`SidebarItem`) match against — keep the two in sync.
- **Inspector sections:** `InspectorSection` enum (in `AppSettings.swift`) drives both visibility and order. Order persists as a JSON string in `AppSettings.inspectorSectionOrder` (new enum cases auto-append). Settings shows a drag-reorderable list (`InspectorSectionRow`, `.draggable`/`.dropDestination`); `InspectView` renders via `inspectorSectionContent(_:)` in that order. The deep-intelligence blocks (intelligence/compare/runbook) stay fixed and are **not** reorderable.
- **Resizable panels:** Sidebar resizes natively via `navigationSplitViewColumnWidth` bounds (the `NSSplitViewDelegate` lock was removed). The inspector resizes via a custom AppKit `ResizeDivider` writing `inspectorWidth` (@AppStorage). `ResizeDivider` must track **window** coordinates, not the divider's local space — see the UI rules note below.

## Safety boundary (never build without explicit ask)

- Do **not** run shell commands, Docker, package managers, or repo mutation from the app.
- Runbook UI wording: **Generate**, **Copy**, **Export**, **Open**, **Refresh** — not Run/Execute/Install.
- No MCP server mode, autonomous agents, or install automation in core paths.

## UI rules (from user preferences)

- **Mac-native polish** — unified window chrome (`.windowToolbarStyle(.unified)`), full-height sidebar flush with content; avoid floating disconnected panels.
- **Main window title** — hide the redundant app title with `MainWindowChromeConfigurator` (PromptVault pattern) plus empty `.navigationTitle("")`. The configurator also **flattens the sidebar split divider**: it walks the `NSSplitView` backing `NavigationSplitView`, sets `dividerStyle = .thin`, and clears the drop shadow on the split view + its arranged subviews so the sidebar edge is a clean 1px hairline (matching the inspector's `ResizeDivider`) instead of the heavy "Finder" shadow. It retries over a few frames (the split view appears late) and is re-applied after each sidebar toggle (`toggleSidebarColumn`).
- **Resizable side panels** — sidebar and inspector are both **user-resizable** (the project list column flexes between them). Sidebar uses native `navigationSplitViewColumnWidth(min:ideal:max:)` bounds (the old `NSSplitViewDelegate` width lock in `MainWindowChromeConfigurator` was removed). Inspector is a fixed-frame `HStack` child whose width (`inspectorWidth`, @AppStorage) is driven by the AppKit `ResizeDivider`. **Resize-divider gotcha:** track the cursor in **window coordinates** anchored at mouse-down, not the divider's local space — the divider slides as the panel resizes, so local-space deltas collapse to ~0 and the resize jitters. Don't "fix" jitter with a blur mask; fix the coordinate math. If exact sidebar parity is wanted, switch the detail+inspector pair to `HSplitView`.
- **Split column dividers** — align sidebar, middle, and detail header dividers with `AlignedSplitColumnHeader` (**38pt** fixed height in `ShelfLayout.swift`). Queue, Ecosystems, Workflows, and My Stack use the same header pattern. **Sidebar alignment gotcha:** macOS gives the sidebar column a larger top safe-area inset than the detail column (measured: sidebar content top 42pt vs detail 32pt), so the sidebar header/divider render lower. `SidebarView` lifts its content with `headerTopAlignmentNudge` (−10) so all three header dividers line up; the sidebar List's `.contentMargins(.top, 11, for: .scrollContent)` is tuned (vs the list's 8pt) so the first sidebar **row** also aligns with the first project row. These are measured constants in points — re-measure with a temporary `GeometryReader`/`PreferenceKey` if the header layout changes.
- **Quick Capture** — after save, clear the project URL/search field for the next repo; place AI suggestions at the top with Generate → Generated / Re-generate; keep Quick Flags for filtering (AI may auto-check when obvious).
- **Title-bar chrome** — the column-header row **is** the title bar (no `.toolbar` items; the system sidebar toggle is removed via `.toolbar(removing: .sidebarToggle)`). Sidebar toggle (leading) + search + inspector toggle (trailing) are `HeaderChromeButton`s in the **project-list header**, posting notifications. Keep the brand (owl) header in the sidebar's `AlignedSplitColumnHeader`; the brand glyph comes from the **app icon** (`ReshelfBrandImage` → `NSImage.applicationIconName`, falling back to bundled `ReshelfBrand.png`) so it always matches AppIcon. Don't reintroduce `.toolbar` items or a second sidebar toggle.
- **Do not use** SwiftUI `.inspector()` on split-view detail — it adds a fourth column; embed extra metadata **inside** the detail pane.
- **Stabilize the main window** (hierarchy, empty states, list/detail) **before** command palette, menu bar extra, or other peripheral capture flows.
- **Floating capture** (Quick Capture sheet, future palette): prefer **solid opaque** surfaces, not heavy glass, so text stays readable over bright windows.
- **Optional chrome** (inspector sections, metadata blocks): should be **hideable via Settings**, not always on.
- **No login / sign-in** — frictionless local tool unless the user explicitly asks otherwise.

## Docs rules

- Project docs use **plain language**; explain jargon inline (SwiftData = Apple’s on-disk model store, GRDB = SQLite toolkit, etc.).
- Do **not** edit attached plan files from the user; use [todo.md](todo.md) and mark items there.
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

- Only commit when the user asks.
- No force-push to `main`/`master`.

## Related workspace context

- Ollama and Pieces are part of the user’s wider workflow; optional future hooks belong in [future-features.md](future-features.md), not assumed in core paths.
- Reference app pattern: PromptVault-style 3-column shelf + capture (see home `AGENTS.md`).
