# Changelog

All notable changes to **reshelf** are documented here. This project follows
[Semantic Versioning](https://semver.org/) loosely while pre-1.0.

## [Unreleased]

### Planned (v2 — first up)
- **GitHub login inside the app** — connect your GitHub account (read-only) to
  improve recommendations and personal-fit. See [v2.0-roadmap.md](v2.0-roadmap.md).

## [1.10.1] — 2026-08-19

### Fixed
- **Intermittent stuck UI after captures and intelligence refreshes.** The
  refresh bus posted its notification on whatever thread called it, and
  NotificationCenter delivers to SwiftUI's `onReceive` on the posting thread.
  The capture and ingestion services emit from background tasks, so every
  capture save or metadata ingest mutated the app's published refresh state
  off the main thread — SwiftUI's "Publishing changes from background threads
  is not allowed" fault, and the source of the app occasionally freezing in
  day-to-day use. The bus now always delivers on the main thread, which fixes
  every emitter at once. Verified live: the capture → fetch → save → ingest
  path runs with zero faults where it used to fire one per save.
- **`--oss-db-smoke` actually works now.** The debug smoke command read the
  schema summary without ever opening the database, so it failed on every run
  since it shipped. It now initializes (and migrates) the database first, which
  is the check it was meant to be.

## [1.10.0] — 2026-08-01

### Added
- **GitHub token in Settings → Capture.** Without a token GitHub allows about 60
  API requests per hour per IP, so bulk imports and busy capture sessions could
  hit "rate limit reached". Paste a personal access token (a fine-grained,
  read-only one is enough) and the limit rises to 5,000/hour — and Quick Capture
  can see your own private repos. The token lives in the macOS Keychain and is
  sent only to the GitHub API; a Test button confirms it works, and the
  rate-limit error now points at the setting when no token is saved.

## [1.9.1] — 2026-07-28

### Fixed
- **Quick Capture from the ⌘K palette no longer closes without opening.** Paste a
  GitHub URL, press Enter, and the palette would dismiss while the capture sheet
  never appeared — after which capture wouldn't open again until you relaunched.

  The cause was the wedge-recovery watchdog added in 1.3.3. After asking for a
  sheet it waited 1.2 seconds and, if no sheet window was on screen *at that
  instant*, declared the app wedged and cleared every sheet binding — including
  the request it had just made. Capture from the palette is the slow path: it can
  spend up to 600ms waiting for the autofill popup to detach, and then a second
  sheet cannot appear until the palette finishes dismissing. A perfectly healthy
  presentation could cross 1.2 seconds and be cancelled by its own watchdog, and
  clearing state mid-presentation left the presenter wedged for good.

  A real wedge is permanent; a slow presentation is not. The watchdog now polls
  instead of sampling once — any check that sees a sheet stands down, and only a
  sheet that never arrives at all is treated as a wedge. A recovery check also
  stands down if a newer request has been made since, so it can no longer cancel
  someone else's sheet.

## [1.9.0] — 2026-07-28

### Added
- **Folders for the shelf.** A folder is a grouping you make — "everything I cloned for
  project X" — deliberately separate from categories (a fixed taxonomy describing what a
  repo *is*) and from shelf status (how much you value it), because a project's worth of
  repos spans all three shelves and a dozen categories. Right-click a project →
  **Add to Folder ▸** (or **New Folder…**). Folders appear in their own sidebar section
  between Library and Categories, shown only once you have one; each row carries a folder
  icon and a live count and filters the list like a category row. Rename and delete from
  the row's context menu. **Deleting a folder only ungroups its projects** — they keep
  their shelf, their clone, their notes and everything else, and the confirmation says
  so. The inspector shows a **Folder** row next to Added / Updated when a project is in
  one. A project belongs to at most one folder, and any project qualifies whether or not
  it's cloned: uncloning must not eject a repo from the group that exists to make the
  cleanup possible.
- **Folders travel with the catalog** — written into JSON exports *and* automatic
  backups, so moving a catalog between Macs (or restoring one) no longer silently drops
  the grouping. On import folders are matched by **name**, case-insensitively, not by id,
  so two Macs that each created a "Photos app" converge on one folder rather than two
  identical ones. An older export that carries no folder for a project leaves that
  project's folder alone.
- **Batch actions.** **⌘-click** toggles a row into a selection, **⇧-click** extends from
  the last plain click, and the footer then shows "N selected" with an **Actions** menu:
  move them all to a shelf, add them all to a folder, remove their local clones, or
  remove them from the catalog. Right-clicking *inside* the selection gives the same
  menu; right-clicking *outside* one still acts on that row alone, so a destructive
  action never lands on rows you weren't pointing at. Both destructive actions confirm
  with a count and say what survives — clones go to the Trash and stay in the catalog,
  catalog removals are backed up first and leave files on disk untouched. The selection
  is kept separate from the inspector's, so building a batch never costs you the detail
  view of what you were last looking at.

### Removed
- **The v2 Intelligence scaffolding is gone** — 78 files. It had been unreachable behind
  a Labs flag since 1.7.0 retired the toggle, so nothing you could use went with it. What
  the shelf actually does is unchanged.

### Changed
- Sorting a project into a folder now counts as a change worth backing up, so a regrouped
  catalog can't look identical to the previous snapshot and go unrecorded.

### Note on updating
This adds a field and a model to the catalog store. Once you're on 1.9.0, **don't open an
older reshelf build** — it can migrate the store backwards and drop them. If you run
reshelf on two Macs, update both.

## [1.8.0] — 2026-07-28

### Fixed
- **Backups no longer miss edits that don't change the project count.** Two things
  were wrong at once. The "has anything changed?" check compared file *sizes*, so
  swapping one value for another of the same length looked identical and nothing
  was written. And nothing reliably ran on quit, so an edit made in a session that
  didn't add or remove a project could go unrecorded entirely. Both fixed: the
  check now compares actual content, and a snapshot is written as the app quits.

### Changed
- **A fresh install starts with nine repos worth having** instead of eight
  internal-tools platforms: jade, Seedling, kika-obsidian-mcp, ollama, Handy, zed,
  excalidraw, lazygit and immich. Existing shelves are untouched — the starter set
  only ever appears when there's nothing to show. (immich is AGPL on purpose, so
  the copyleft caution introduces itself rather than surprising you later.)
- Removed the last of the cloud-AI plumbing left behind in 1.7.0. Nothing to see —
  it was already unreachable.

## [1.7.0] — 2026-07-28

### Changed
- **Settings is four short tabs instead of one long scroll.** General holds
  Appearance, Licenses and the Agent Skill installer; **Capture** holds Capture
  Assist; **Library** holds where repos are cloned and how the inspector is laid
  out; About is unchanged. The window also opens large enough that the fullest
  tab fits without scrolling.
- **There's no AI provider to choose any more — reshelf generates on-device, full
  stop.** The AI Providers settings are gone. In practice this changes nothing
  about what you got: Capture Assist always used on-device Apple Intelligence and
  never consulted that setting. The picker was offering a choice it didn't make.

### Added
- **The inspector shows when a project last changed.** An **Updated** row sits
  under **Added**, so the date the *Recently Updated* sort orders by is one you
  can actually see. Entries whose date isn't known yet simply don't show the row.

## [1.6.0] — 2026-07-27

### Added
- **Sort by what's actually alive.** A new **Recently Updated** sort orders the
  shelf by when each project last changed upstream, not by when you happened to
  save it — so the things still moving float to the top and the abandoned ones
  sink. New captures pick the date up automatically.
- **Fill it in for everything you've already cloned, in one click.** Settings ▸
  General ▸ **Fill "Last Updated" from Clones** reads each cloned repo's last
  commit straight off your disk. Offline, instant, no GitHub rate limit. Repos
  you haven't cloned fill in the next time their details are fetched; until then
  they sort to the bottom rather than pretending to be ancient.
- The date rides along in your exported catalog JSON, so it survives the trip to
  another Mac.

### Fixed
- **The top of the sidebar isn't blurry any more.** macOS 26 already tried to
  paint a frosted band over the first rows and reshelf pushed back; macOS 27
  started drawing a second one from a different place, and it slipped past. Both
  are handled now, so "All Projects" and the rows under it stay sharp.

## [1.5.1] — 2026-07-27

### Fixed
- Housekeeping release. Nothing to see — it exists to prove the new in-app
  update path works end to end, by being something for 1.5.0 to update to.

## [1.5.0] — 2026-07-27

### Added
- **reshelf updates itself.** New versions arrive in the app instead of as a DMG
  you download and drag. reshelf checks once a day in the background, shows you
  what changed, and installs only when you say so — nothing happens behind your
  back. There's a **Check for Updates…** item in the reshelf menu for when you're
  impatient, and a switch in Settings ▸ About to turn the automatic checking off.
  Update checks send nothing about your machine.

  One catch, once: 1.4.0 has no updater in it, so 1.5.0 is the last version you
  install by hand.

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
