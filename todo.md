# Todo

Near-term work for **reshelf**. Check off as you go. Agents: do not recreate this list elsewhere — update here only.

## To do (added 2026-06-13)

- [ ] 🐞 **Fix the header toolbar icons (title-bar click bug)** — the sidebar-toggle, sort, search, and inspector icons in the column header don't respond to real mouse/trackpad clicks. The header is laid out flush in the macOS title-bar band (`titlebarAppearsTransparent` + `.fullSizeContentView` + `.ignoresSafeArea(.top)`), so the system `NSTitlebarView` sits in front and eats the clicks (turns them into window-drags). ⌘K works, so only click *delivery* is broken. **Note:** automated/accessibility clicks false-pass — test with a real click. Fix direction = render the header inside an `NSTitlebarAccessoryViewController` instead of fighting the title bar. Full diagnosis + dead ends captured in `../reshelf-claude/CLAUDE.md`. Keep the look (change only as much as needed to make it work).
- [ ] **⌘⇧U — show clones needing updates first** — after *Check Clones for Updates* runs, sort the repos that have updates available (the orange-dot / "behind" ones) to the **top** of the list, instead of leaving them in place.
- [ ] ⏳ *[later]* **Extend the reshelf skill beyond cloned repos** — a skill like the current one, but running across the whole **Collection** and **Top Shelf**, not just cloned repos. The current cloned-repo skill works great; this is an expansion for later.
- [x] **Remove the empty "Format" menu** from the top macOS menu bar — done in 1.3.0: pruned at the AppKit level (`FormatMenuPruner`), survives menu-bar rebuilds.
- [ ] 💡 *[nice-to-have]* **Show changelog on clone update (no AI)** — when pulling updates for a cloned repo, optionally surface the incoming commits/changelog using plain git (no AI, like today) so you can see what changed. Not a must, but would be nice.

## Done in 1.3.0 (2026-07-17)

- [x] **Capture Assist** — on-device Apple Intelligence fills use cases / note / tags; auto-generate after every save (default on) + **Fill Missing Entries** backfill in Settings; strictly fill-only. Un-parked commit 489841a and built on it with guided generation into the capture form.
- [x] **Inspector duplicate GitHub stats removed** — Metadata on top is the single source; GitHub section only shows unique topics/description; settings row renamed "GitHub Topics".
- [x] **About tab in Settings** — icon, version, tagline, links (akakika.com / GitHub / X).
- [x] **Install reshelf skill from Settings** — bundled in the app, copies to `~/.claude/skills/reshelf`.
- [x] **Menu audit** — all 19 menu actions verified wired; empty Format menu removed.

## Next up (v2) — after v1 testing

- [ ] ⭐️ **GitHub login inside the app** (FIRST v2 item) — in-app "Connect GitHub" flow: OAuth device flow (primary) + fine-grained PAT (fallback), token in **Keychain**, read-only. Full spec in [v2.0-roadmap.md](v2.0-roadmap.md).

## Documentation and repo

- [x] Add [README.md](README.md) with “In one minute” and build steps
- [x] Add project [AGENTS.md](AGENTS.md) with architecture + contributor rules
- [x] Align [features.md](features.md), [goals.md](goals.md), [future-features.md](future-features.md) with README/AGENTS
- [x] Add `.gitignore` (`.build/`, `DerivedData/`, `.DS_Store`, `xcuserdata/`)
- [x] App icon — owl artwork ships as a loose `AppIcon.icns` (Info.plist `CFBundleIconFile = AppIcon`). Regenerated the `.icns` from the 1024px `AppIcon.png` with a full 10-representation iconset via `iconutil` (the old one had only an `ic12` rep, so macOS fell back to the generic icon)
- [x] About window — native About panel (app menu → About reshelf) with version + reshelf tagline (`OpenSourceShelfApp.showAboutPanel`)
- [x] Configure GitHub remote and push

## Main window polish (do before ⌘K palette)

- [x] Empty states: no selection, empty filter, no search hits
- [x] **Daily Briefing** sidebar — removed until a real filter is defined
- [x] Confirm `.toolbar` only on detail column if adding toolbar items
- [x] Icon fetch: lazy per row; failures do not block list scrolling

## Intelligence layer (GRDB)

- [x] Quick Capture / Add Project upsert `RepositoryRecord` + metadata via `CatalogCaptureIntelligenceService`
- [x] Read path: show intelligence metadata in inspector when linked
- [ ] Document `~/reshelf/` layout in README when bridge ships
- [x] Metadata refresh on save (via `RepositoryIngestionService.ingestMetadata`)

## Quick Capture and AI

- [x] GitHub errors: rate limit, 404, private repo — clear user messages (`QuickCaptureService` maps 404/401/403+429/rate-limit headers to specific `CaptureError`s shown in the Quick Capture sheet)
- [x] Ollama offline: disable AI step with explanation — generalized to be **provider-aware** (Quick Capture pre-flights the resolved AI provider; "Generate with AI" disables with a reason when nothing is configured, Apple Intelligence isn't wired, or Ollama is unreachable)
- [ ] Document Ollama prompt in code comment or dev doc; shorten use-case bullets
- [ ] Apple Intelligence: implement or hide Settings toggle

## UX (after main window stable)

- [x] Command palette (⌘K) — search, recent searches, GitHub URL → Quick Capture with auto-fetch
- [x] Settings toggles to hide optional inspector sections
- [x] Inspector sections drag-to-reorder in Settings (order persists, honored by InspectView)
- [x] Auto-categorize Quick Capture + retroactively re-categorize existing projects (`CategoryClassifier`)
- [x] Resizable sidebar + inspector (sidebar native bounds; inspector via `ResizeDivider`, jitter fixed)
- [x] “Mark checked today” for `lastCheckedDate` (repo row right-click → Mark Checked Today)

## Data and privacy

- [x] Export catalog (+ later intelligence) to JSON (File → Export Catalog as JSON…, ⌘⇧E; `CatalogExportService` writes a versioned, re-importable snapshot via save panel — icon bytes excluded)
- [ ] README privacy section: when GitHub/Ollama are called (see README network table)

## Release prep

- [x] Clean Mac first-run test (seed data, GRDB create, no duplicate init) — **PASS**. With `~/reshelf` moved aside (true new-user state), launch creates the SwiftData store, seeds exactly **8** projects (no double-seed), creates the GRDB `opensource-shelf.sqlite`, writes one backup snapshot, no crash. Benign note: on a machine that already has a shared `~/Library/Application Support/default.store`, `CatalogStoreLocation.migrateAndResolve()` copies it once, so CoreData logs harmless persistent-history truncation for unrelated entities; a genuine fresh install has no such store and stays silent.
- [x] `xcodebuild` CI-style build on macOS

## Done recently

> Full release history is in [CHANGELOG.md](CHANGELOG.md); this is the working dev log.

- **2026-07-23 (1.3.2: clone reliability + SwiftUI classification)** — Fixed the **serial-clone freeze**: `GitClient.run` waited for exit before reading pipes (deadlock past ~64KB of git output) *and* parked a Swift-concurrency cooperative thread per git call — a few clones in a row starved the pool; output is now drained on GCD while git runs, exit awaited via `terminationHandler`. Fixed **stale clone badges**: the per-launch clone index never self-healed a stale *miss*, so a clone that appeared outside the app showed un-cloned and re-cloning errored; the index now rescans on `didBecomeActive`, `clone()` rescans before going to the network, and an existing checkout of the same repo at the destination is **adopted** instead of refused. Reversed the 07-16 "manual-only" decision below: added a **SwiftUI classifier rule** ranked just above macOS (safe now — since classifier v4 the launch pass never overwrites stored meaningful categories, so no reshuffle risk; apps with macos/menubar signals still outscore the lone swiftui topic). One-time migration re-filed 10 macOS rows → SwiftUI and moved their 6 clones on disk. Docs updated (CHANGELOG/features/AGENTS/todo).

- **2026-07-16 (SwiftUI category)** — Added a **SwiftUI** sidebar category (`SidebarItem.swiftUITools`, swift icon, exact `"SwiftUI"` match, placed after macOS) for iOS/SwiftUI UI libraries. Manual-assign only — `CategoryClassifier` untouched on purpose ("swiftui" stays a macOS signal; adding a competing rule would risk reshuffling existing shelves on tie-breaks). Docs updated (CHANGELOG/features/todo).

- **2026-06-03 (post-1.0 batch + public-repo prep)** — Shipped, on top of the v1 clone/updates work below: clones **grouped by category** (`~/reshelf/repos/<Category>/<repo>`, with launch migration); **dynamic sidebar categories** + classifier hardening (no raw language-name categories); **shelf keyboard moves** (⌘T/⌘Y/⌘⇧G) + recolored badges (blue/gray/amber); **list sorting** (Recently Added / Name / Stars); **Enter-to-save** in Quick Capture; **duplicate protection** (capture guard + `Remove Duplicate Repos`); **license explainer** popover + strict-license caution + Settings toggle; clone-index **perf cache** (O(1) `isCloned`); update-dot sync after pull. Added the **Claude Code skill** under `extras/reshelf-skill/`. Cleaned the repo for public release (removed stray root `AppIcon.icns`/`Info.plist`/`generate_xcode.py`/`AppIcon.iconset`; refreshed README/goals/features/future-features/AGENTS/CHANGELOG).
- **2026-06-03 (v1 clone + updates + Cloned filter)** — Shipped v1 local-clone with **no AI and no `git-lfs` requirement** (LFS smudge/clean/process filters bypassed in `GitClient`, full clone via `blobless: false`). Clone from the repo right-click menu or the inspector's **Local Copy** section to `~/reshelf/repos/<repo>` (flat naming; `<owner>-<repo>` only on a real collision, verified against `.git/config` origin). Rows show a **cloning spinner** then a **disk badge**; cloning no longer auto-opens Finder. Added a plain-git **update check**: opening a cloned repo's inspector runs a read-only `git ls-remote origin HEAD` (`GitClient.remoteDefaultHead`) and shows **✓ Up to date** / **↑ Updates available** + one-click **Pull** (`pullFastForward`); `CatalogCloneService.UpdateStatus/updateStatus/pull`. **File → Check Clones for Updates** (⌘⇧U) batch-checks every clone and flags behind ones with an **orange dot** on the row badge (`behindProjectIDs`). New **Cloned** sidebar filter (`SidebarItem.cloned`, filesystem-derived via `isCloned`, filtered in-memory, live count). On-demand only — no background polling. Deleted old owner-nested orphan clones. Docs updated (README/features).
- **2026-06-02 (simplify v1 → catalog)** — Moved the entire **Intelligence engine to v2**, gated behind the single `LabsFeatures` flag (off by default); **no engine code deleted** (dormant for v2). With Labs off the default app is a pure **catalog**: gated the per-repo Fetch-Intelligence/Reveal-Clone/Runbook/Compare context-menu items + the row intelligence badges (`ProjectListView`); the inspector's clone/runbook/AI-insight/stack/relationships/recommendations sections (`InspectView`, `InspectorSection.isIntelligence`); the Quick Capture "Generate with AI" step (`QuickCaptureSheet`); the **Catalog** + **Actions** menus, **Queue**, and Explore (`OpenSourceShelfApp`); and the **AI Providers** tab + **Repository Storage** card + intelligence inspector-section rows (`SettingsView`). Reframed the Labs toggle as **"Enable Intelligence (v2 preview)"**. Docs updated (README/features).
- **2026-06-02 (data safety)** — Hardened catalog persistence after a data-loss incident (catalog had been on the shared `~/Library/Application Support/default.store` and got reset to seeds). Four layers now: (1) **isolated store** at `~/reshelf/catalog.store` (off the shared default, one-time copy-migration); (2) **automatic JSON backups** to `~/reshelf/backups/` on every add/remove + on app background, last 30 kept, full-fidelity (`CatalogBackupService`, shares the export Codable schema); (3) **auto-restore-on-empty** — on launch, if the catalog is empty but a backup with data exists, restore instead of seeding (`restoreIfCatalogEmpty`, gated before `SeedData`); (4) **File → Restore from Backup…** picker (non-destructive merge). Also added **File → Import GitHub URLs…** (`ImportURLsSheet`) — bulk-add/restore from a URL list (used to recover ~24 repos carved from the wiped store's freed SQLite pages).
- **2026-05-31 (compare redesign)** — Reworked the Compare screen. **Main area is now two modes:** a repo **picker in place** (selection) that flips to the **results view** when you Run comparison; header swaps Run ⇄ favorite/export/**Edit Repos** (no more cramped picker column or pop-up). Results lead with a **winner hero card**, **ranking cards with score bars**, the **comparison matrix moved up** (winner column highlighted + zebra rows), then **Decision summary** (moved out of the inspector) and tidy **detail cards**. The **inspector is now a per-repo deep dive** (defaults to the winner, follows ranking clicks): metrics grid, summary, why-it-ranked, strongest/weakest signals, stack, ecosystems, risks. Compare backgrounds unified with the window.
- **2026-05-31 (chrome cleanup)** — Unified the three columns + title-bar on `windowBackgroundColor`, flattened the vibrant sidebar/title-bar materials to a flat opaque surface (within-window blending) so the sidebar reads edge-to-edge like Claude, removed the system title-bar separator, and kept the fine aligned hairline under the header row.
- **2026-05-31 (row menu + settings tabs)** — Enriched the repo-row right-click menu (`ProjectListView.catalogContextMenu`): grouped Open on GitHub / Open Website / Copy GitHub URL · Fetch Intelligence (Clone & Analyze) / Reveal Clone in Finder (when a tracked clone exists) / Generate · Open Runbook · Add to Compare (Labs) · **Mark Checked Today** · **Remove from Catalog…** (destructive, confirmation dialog; leaves clones + intelligence data untouched). Reorganized **Settings into a 3-tab `TabView`** — **General** (Appearance, Labs, Repository Storage), **AI** (preferred provider + Ollama/Apple Intelligence/cloud cards + Intelligence auto-runbook), **Inspector** (section visibility + drag-reorder).
- **2026-05-31 (fix queue)** — Worked the handoff fix queue, re-applied onto `sidebar-catalog-first` (the live branch) after an initial pass landed on a stale base. **GitHub error handling:** `QuickCaptureService.getJSON` maps 404 → "not found / may be private", 401 → unauthorized, 403/429 + `X-RateLimit-Remaining`/`X-RateLimit-Reset` → rate-limited with a "try again in N min" hint, others → generic; surfaced in the Quick Capture sheet. **AI offline UX (provider-aware):** Quick Capture pre-flights `AICompletionService.resolvedProvider`; "Generate with AI" disables with a specific reason when no provider is configured, Apple Intelligence isn't wired, or the resolved Ollama server is unreachable, and a failed run flips it back. **JSON export:** File → Export Catalog as JSON… (⌘⇧E) → `CatalogExportService` writes a versioned snapshot via `NSSavePanel` (icon bytes excluded). **About window:** native About panel (app menu → About reshelf). App icon artwork still pending (no `Assets.xcassets/AppIcon`); GitHub remote still needs the user. Build green; app launches and runs.
- **2026-05-31 (simplify)** — Workflow pins use `SidebarItem` lanes (dropped `WorkflowLane`); unified `CatalogListSelection`; pin/catalog dedupe + add-to-catalog removes pin; Labs toggle gates Compare/Explore menus (default off).
- **2026-05-31 (workflows)** — My Workflows lanes can pin **public GitHub repos** and **local project folders** (`WorkflowPin` in SwiftData). List shows **Pinned** + **From Catalog** sections; inspector supports open/remove/notes and **Add to Catalog** for repo pins.
- **2026-05-31 (sidebar)** — Re-sectioned sidebar into **Library** / **Categories** / **My Workflows**; removed Compare, Ecosystems, Workflows, and My Stack from the sidebar (View + Window → Explore menus). Wired discovery cluster selection to `DiscoveryClusterInspectorView` with catalog jump from repo rows.
- **2026-05-31 (latest)** — Renamed the product to **reshelf** (`PRODUCT_NAME`; built bundle `reshelf.app`, menu-bar/`CFBundleName` = reshelf) while keeping the Xcode target/module + bundle ID as `OpenSourceShelf` / `com.kika.opensourceshelf`. Added `LegacyNameMigration` (moves `~/OpenSourceShelf` → `~/reshelf`, renames `OpenSourceShelf.*` UserDefaults keys → `reshelf.*`). Merged the title bar into the column-header row (removed `.toolbar` items + the auto sidebar toggle; controls moved into the project-list header as `HeaderChromeButton`s). Flattened the sidebar divider to a 1px hairline; aligned the three header dividers + the first sidebar row (measured constants). Sidebar brand now uses the app icon. Added **Repository Storage** setting (user-selectable clone folder, defaults to `~/reshelf/repos`).
- **2026-05-31 (later)** — Settings moved to a standard macOS `Settings` scene window (app menu → Settings…, ⌘,); removed the in-app settings panel + sidebar button. Cleaned the menu bar (removed the status-bar menu extra, deduped the View menu, dropped Navigate, folded Queue into Window). Added **Appearance** (System/Light/Dark) via `@AppStorage` + `.preferredColorScheme` on every scene; dark mode works app-wide off existing semantic colors.
- **2026-05-31** — Auto-category classifier (GitHub topics/description/language → meaningful category) for Quick Capture + retroactive re-categorization on launch. Inspector sections now show/hide **and** drag-to-reorder in Settings (order persists, honored by InspectView). Made sidebar + inspector resizable: unlocked the sidebar divider (native `navigationSplitViewColumnWidth` bounds) and fixed inspector resize jitter (`ResizeDivider` now tracks window coords, not the moving divider's local space).
- **2026-05-28** — Command palette (⌘K) with search, recent searches, GitHub URL capture → auto-fetch Quick Capture. Sidebar header icons (sidebar/search/inspector toggle) matching Claude Desktop style. Removed inline search bar, replaced with clean title header + active search chip. Item-based sheet for QuickCapture URL passthrough.
- **2026-05-27** — Catalog list empty states; removed Daily Briefing sidebar; Settings inspector section toggles; Quick Capture GRDB upsert; lazy icon fetch; initial git commit.
- **2026-05-25** — Added README, AGENTS.md, and refreshed features / goals / future-features / todo from codebase + user AGENTS rules.
