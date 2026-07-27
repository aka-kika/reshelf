# Changelog

All notable changes to **reshelf** are documented here. This project follows
[Semantic Versioning](https://semver.org/) loosely while pre-1.0.

## [Unreleased]

### Planned (v2 — first up)
- **GitHub login inside the app** — connect your GitHub account (read-only) to
  improve recommendations and personal-fit. See [v2.0-roadmap.md](v2.0-roadmap.md).

## [1.4.0] — 2026-07-27

### Added
- **Import Catalog from JSON (⇧⌘I).** Export has always written a portable
  catalog file, but nothing could read one back — so moving a shelf to another
  Mac was a one-way trip. File ▸ Import Catalog from JSON… now takes any
  reshelf export (or any automatic backup — same format) and shows what it will
  do before touching anything: how many projects are new, how many you already
  have. New projects are always added; matching ones are left alone unless you
  tick **Also update the projects I already have**, which replaces their details
  with the file's version. Projects are matched by GitHub URL, so importing the
  same file twice never duplicates. A backup is taken first, so any import can
  be undone from Restore from Backup.
- **Exports now carry "Why I Saved This."** `personalNote` was missing from the
  export format, so a round-trip through JSON silently dropped every personal
  note. It's included now. Older exports that predate the field still import
  fine, and importing one never blanks a note already on the project.

## [1.3.3] — 2026-07-23

### Fixed
- **Sheets can no longer wedge the app.** The rare macOS ViewBridge exception
  (an autofill popup still attached to a text field while a sheet presents)
  could leave SwiftUI convinced a sheet was open when none was — after which
  Quick Capture, Add, Edit, and the palette silently never appeared again until
  a force-quit. Rapid serial Quick Captures could trigger it. Two-layer fix:
  presentation now *waits until the autofill popup has actually detached*
  (instead of hoping one runloop turn is enough), and a watchdog detects a
  sheet that was requested but never appeared and resets the phantom state, so
  the very next attempt works.

## [1.3.2] — 2026-07-23

### Added
- **SwiftUI is a category the classifier can actually produce.** The sidebar
  has had a SwiftUI shelf all along, but every SwiftUI repo scored as macOS and
  landed there instead. A new SwiftUI rule (ranked just above macOS) sends
  SwiftUI component/animation/library repos to the SwiftUI shelf, while mac
  *apps* that merely use SwiftUI still win macOS. Library-shaped wording
  ("SwiftUI library", "for SwiftUI", renderer/component/framework) tips
  cross-platform packages whose platform tags used to drag them into macOS.

### Fixed
- **Cloning several repos in a row no longer freezes the app.** Every git call
  parked a Swift-concurrency thread for its whole run and read git's output
  only after waiting for exit — so a chatty clone or fetch could deadlock on a
  full pipe and each one ate a thread for good. Git output is now drained while
  the process runs, off the concurrency pool, and exit is awaited without
  blocking anything.
- **Clone status can't silently go stale anymore.** The per-launch clone index
  only self-healed when an indexed clone disappeared — a clone that *appeared*
  behind its back (restored from the Trash, cloned outside the app) showed as
  un-cloned, and re-cloning it failed with a confusing error. The index now
  rescans when the app returns to the foreground, Clone re-checks the disk
  before hitting the network, and a checkout of the same repo already sitting
  at the destination is adopted instead of refused.

## [1.3.1] — 2026-07-18

### Added
- **"Why I saved this" — a personal note on every repo.** You clone things for a
  reason; now the reason is saved with them. A quiet collapsed row in the
  Inspector (click to read or edit inline — saves as you type), a **Why** field
  in Quick Capture for the moment you shelve it, and a matching field in the
  Edit sheet. Searchable, with its own visibility toggle in
  **Settings → Inspector**. Yours alone: Capture Assist and every other
  automated fill never touch it.

### Fixed
- Sheets (Quick Capture, Add/Edit, palette) now present after ending text
  editing, avoiding a rare macOS ViewBridge freeze when a sheet opened while an
  autofill popup was attached to a focused text field.

## [1.3.0] — 2026-07-17

### Added
- **SwiftUI category** — a sidebar shelf for SwiftUI/iOS UI libraries (swift
  icon, exact `SwiftUI` category match). Sidebar and Categories menu only; the
  auto-classifier is untouched ("swiftui" stays a macOS signal — assign this
  category manually via Edit).
- **Capture Assist — the one AI feature in the main app, fully on-device.**
  Quick Capture can now fill **use cases, a note, and tags** using **Apple
  Intelligence** (FoundationModels guided generation). Zero setup, no API keys,
  nothing leaves your Mac. Controlled from **Settings → General → Capture Assist**:
  - **Auto-generate on every capture** (on by default) — runs in the background
    right after you save, so capture stays paste → Enter → Enter; results appear
    on the entry a couple of seconds later.
  - **Fill Missing Entries** — backfills use cases for already-shelved entries
    that have none. Strictly fill-only: entries with use cases are skipped, and
    fields you typed are never overwritten.
  - A manual **Generate** step stays in Quick Capture's More Details for
    pre-save control. Requires a Mac with Apple Intelligence (macOS 26+);
    the app runs fine without it — the section simply doesn't appear.
- **About tab in Settings** — app icon, version, tagline, and links
  (akakika.com, GitHub, X).
- **Install the reshelf skill from Settings** — Settings → General → Agent Skill
  copies the bundled `reshelf` Claude Code skill to `~/.claude/skills/reshelf`
  (a previous install goes to the Trash first, never deleted).
- **Apple Intelligence is a real AI provider** — the Labs provider stub is now
  wired to on-device FoundationModels for suggestions and repo analysis
  (guided generation, no JSON-parsing failure mode).

### Changed
- **Inspector de-duplicated** — stars/language/license no longer repeat in the
  GitHub section; the Metadata section on top is the single source. The GitHub
  section now only appears when it has something the catalog entry doesn't
  (fresh topics, a distinct description), and its row in Inspector settings is
  renamed **GitHub Topics**.

### Fixed
- **Empty Format menu removed** from the menu bar (pruned at the AppKit level,
  and it stays gone when the menu bar rebuilds).

## [1.2.1] — 2026-07-03

### Added
- **Frontend and Games categories** — motion-style web libraries and game engines
  (godot) finally have shelves, in the sidebar and the classifier.

### Changed
- **Auto-categorization got smarter and safer.** New signals: terminal emulators
  → CLI, journaling → Knowledge, task trackers / Trello alternatives / office
  suites → Workspace, speech-to-text → AI / Agent, CSS frameworks & styling
  systems → Design, social-media scheduling → Automation, file management →
  Utility; plus fewer stack-tag misfires (a Postgres-backed app is no longer
  "Database", a React-built app is no longer "Frontend"). And the important one:
  **the classifier never overwrites an existing category** — your manual sorting
  is untouchable; upgrades only fill uncategorized rows (backup taken first).

## [1.2.0] — 2026-07-03

### Added
- **Third Claude Code skill: `reshelf-collector`**
  ([`extras/reshelf-collector-skill/`](extras/reshelf-collector-skill)) — completes
  the trio: `reshelf` reads cloned source, `reshelf-catalog` indexes the whole
  shelf, and this one resurfaces **the rest** — The Collector middle (Yard Sale
  always excluded), with clone status and shelf age, leading with the
  longest-shelved picks you never cloned.

### Changed
- **Quick Capture redesigned** — after Fetch you get a repo identity card (owner
  avatar, name, ★ stars, license in plain words with the ⓘ explainer, language
  chip, one description, website link) plus the only two capture-time decisions
  (Shelf — never truncates — and Category); everything else collapses behind a
  full-row **More details** toggle. Short sheet before fetch, card-sized after.
  Paste → Enter → Enter unchanged.
- The ⌘K command palette closes on a click anywhere outside it (not just Escape).
- Quick Capture header dropped the bolt icon.

## [1.1.0] — 2026-07-03

### Added
- **Remove Local Clone** — right-click a cloned repo → *Remove Local Clone…* moves
  the cloned folder to the Trash (recoverable, with a confirm dialog) and tidies an
  emptied category folder. The catalog entry stays and can be cloned again anytime.
- **Quick shelf moves** — ⌘T → Top Shelf, ⌘Y → Yard Sale, ⌘⇧G → The Collector for
  the selected repo (plus a **Shelf** menu), so you can sort right after capturing.
- **List sorting** — header sort menu: Recently Added (default), Name (A–Z), Most Stars.
- **Cloned sidebar filter** — see only repos you've cloned to disk.
- **Clones grouped by category** — `~/reshelf/repos/<Category>/<repo>`, so you can
  point an AI agent at one category folder. Existing flat clones migrate on launch.
- **Dynamic categories** — the sidebar shows a row for every category in use (live
  count), and the classifier was hardened (no more raw language names as categories).
- **License explainer** — an ⓘ next to any license opens a plain-language popover
  (what you *can* / *must* do); an optional Settings toggle auto-cautions for
  copyleft / source-available licenses (GPL, AGPL, MPL, BUSL…).
- **Duplicate protection** — capture blocks a repo already in the catalog;
  **File → Remove Duplicate Repos…** cleans up existing duplicates (keeps the best
  copy, backs up first).
- **Enter-to-save** in Quick Capture (paste → Enter → Enter, no mouse).
- **Claude Code skill** ([`extras/reshelf-skill/`](extras/reshelf-skill)) that uses
  your clone library as a working reference (learn / use).

### Changed
- **Shelf badge colors** — Top Shelf blue (keeper), The Collector gray (neutral),
  Yard Sale amber (needs review).
- **More precise auto-categories** — the classifier now scores weighted signals
  from topics, description, and repo name (word-boundary matched) instead of
  taking the first keyword hit, so strong signals ("airtable-alternative",
  "menubar") beat broad ones ("api", "dashboard"). Fixes misfires like the topic
  "storage" landing in AI / Agent.
- **Sidebar brand header** — just the owl + "reshelf", no "repo shelf" subtitle.

### Fixed
- **Header buttons finally click** — the merged title-bar/header row looked right
  but its controls (sidebar toggle, sort, search, inspector toggle) ignored real
  mouse clicks: the system title-bar layer claimed them as window drags before
  they could reach the buttons (keyboard shortcuts always worked). An invisible
  click-router now lives in the title-bar layer itself — transparent catchers
  over each control fire the button's own action (menus open natively), empty
  header space still drags the window, and the design didn't move a pixel.
- **Header dividers align again** — on macOS 26+ ("Liquid Glass") the system
  re-imposed a top inset per split column, pushing the list/detail headers below
  the title bar and breaking the one-line divider. All three columns now lay out
  from the window top by construction (no measured nudge constants).
- **Dark mode gray band** — the macOS 26+ title-bar backdrop (`NSScrollPocket`)
  painted a gray strip over the header row; it's now hidden and kept hidden, in
  both appearances and across light/dark switches.
- **Sidebar divider line is back** — macOS 26+ renders the split view's own
  divider zero-width, leaving no line between sidebar and list; the sidebar now
  draws the same 1px hairline the inspector divider uses.
- **Deleting a clone in Finder updates the app** — the Cloned badge, count, and
  sidebar filter now notice a manually deleted clone folder right away (stale
  clone-index entries self-heal) instead of waiting for a relaunch.
- App icon rendered generic — regenerated a complete `.icns` (all sizes).
- Clicking felt slow — the clone lookup is now a cached index (O(1)), not a
  filesystem walk per row.
- The "updates available" row dot now clears immediately after a pull.

## [1.0] — 2026-06-03 (v1: the Catalog)

First testing release. v1 is a clean, local-first **catalog** with zero setup;
the Intelligence engine ships dormant behind a Labs flag (off by default).

### Added
- **Catalog** — capture repos from GitHub (Quick Capture, ⌘⇧N / ⌘K palette),
  auto-categorized; organize onto shelves: **Top Shelf**, **The Collector**
  (default), **Yard Sale**.
- **Sidebar filters** — All Projects, the three shelves, **Cloned**, plus
  auto-classified category filters.
- **Local clone (no AI, no git-lfs)** — clone a full copy to `~/reshelf/repos`
  from the row menu or inspector; cloning spinner + disk badge; LFS filters
  bypassed so LFS repos still clone.
- **Update checks / pull** — read-only `git ls-remote` shows *up to date* vs
  *updates available* with a one-click **Pull**; **File → Check Clones for
  Updates** (⌘⇧U) sweeps all clones and flags behind ones with a dot.
- **Data safety** — isolated SwiftData store, automatic JSON backups (last 30),
  auto-restore-on-empty, manual Restore from Backup, and Import GitHub URLs.
- **Export** catalog as JSON (⌘⇧E).
- **Settings** — Appearance (System/Light/Dark), inspector section show/hide +
  drag-reorder, Repository Storage folder, and the Labs (v2 preview) toggle.
- App icon (owl).
- **Signed & notarized universal DMG** (Apple Silicon + Intel) on the
  [Releases](https://github.com/aka-kika/reshelf/releases) page — built by
  `scripts/release.sh`.

### Notes
- The **Intelligence engine** (clone + AI analysis, runbooks, Compare,
  Ecosystems) is a **v2 preview** behind **Settings → Enable Intelligence**
  (off by default). No engine code is removed; it's dormant for v1.
