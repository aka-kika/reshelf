# Features

What **reshelf** does today. Plain-language map of the app — see [README.md](README.md) to run it.

## Main window (what you use daily)

- **Three columns** — sidebar (owl app-icon branding), project list (title + controls header), inspector pane. The sidebar and inspector are **user-resizable** by dragging their dividers; the project list flexes between them.
- **Merged title bar** — the header row doubles as the window title bar (no separate empty toolbar band). The controls live in the project-list header: a **sidebar toggle** on the left, **search** (⌘K) and **inspector toggle** on the right. Toggles stay visible even when their panel is collapsed, so you can always reopen it. The three column header dividers line up as one clean line, and the sidebar edge is a thin hairline (not a heavy macOS shadow).
- **Command palette** (⌘K) — floating sheet with search field, recent searches, live project filtering. Paste a GitHub URL → "Capture this repository" row appears → click or press Enter → Quick Capture opens with repo info auto-fetched. Escape dismisses.
- **What's new** — a sheet with the release notes (`docs/release-notes/<version>.md`) once after each update, and from **Help → What's New in reshelf**.
- **Menu bar** — File (Quick Capture ⌘N / Search / Export / Import / Restore / **Check Clones for Updates** ⌘⇧U), View (column toggles + navigation), and the app menu (Settings, About, Check for Updates). No status-bar menu extra.
- **No sign-in** — local app only.
- **Seed library** — on first empty launch, nine repos worth having are inserted once (jade, Seedling, kika-obsidian-mcp, ollama, Handy, zed, excalidraw, lazygit, immich). Only ever when there is nothing to show.

## Data safety

- **Isolated store** — the SwiftData catalog lives at `~/reshelf/catalog.store` (next to the intelligence DB), not the shared `~/Library/Application Support/default.store`. A non-sandboxed app sharing the default store risks a destructive reset from any other SwiftData app or schema-divergent build.
- **Automatic backups** — 2 seconds after the last save (a shelf move, a tag, a note, a folder change, an add or a delete — so a bulk import is still one snapshot), every time the app backgrounds, and on quit, a full-fidelity JSON snapshot is written to `~/reshelf/backups/` (last 30 routine snapshots kept; a labelled backup taken before a big change is kept as well). If the backup before a delete or a Yard Sale move cannot be written, that change does not run. Same schema as **File → Export Catalog as JSON…** (⌘⇧E), so backups and exports are interchangeable.
- **Auto-restore-on-empty** — on launch, if the catalog is empty but a backup with data exists, it restores from the backup instead of seeding defaults (so a transient empty state can't silently destroy a real catalog). Not when you emptied the shelf yourself: deleting the last repo is remembered, and the next launch stays empty.
- **Manual recovery** — **File → Restore from Backup…** lists snapshots (date, count, and a label like "Before moving 12 repos to Yard Sale" for the backup taken before a big change). Restoring adds back the repos the catalog lost; **Also put back changes to repos I still have** also returns changed repos to the backup's shelf, tags, notes (including why you saved it) and folder, with a live count first. Name, links, description and category stay as they are. That is the undo for Yard Sale moves, updating imports and duplicate merges. A backup of the current state is written before every restore. **File → Import GitHub URLs…** bulk-adds a pasted list of repos (also the path to rebuild from a recovered URL list); **Stop** ends it after the current repo, and at GitHub's rate limit it stops by itself and keeps the links not imported yet for the next run. A link that failed (offline, or a repo GitHub wouldn't return) stays in the box too.
- **Save by link** — `reshelf://add?url=<GitHub repo URL>` saves a repo into The Collector from another app (Undrdr Drop's "Send to reshelf"); duplicates are only selected.
- **No duplicates** — capture (Quick Capture, Import URLs) detects when a repo is already in the catalog by normalized `owner/repo` (so `https`/`www.`/trailing slash/`.git`/case all match) and blocks the save with an "already in your catalog" notice. **File → Remove Duplicate Repos…** cleans up any pre-existing duplicates, keeping the best-filled copy of each (higher shelf, your own "why I saved this", notes and folder, richer data, then the original) and saving a backup first. Nothing typed on a dropped copy is lost: its tags and use cases are joined into the kept one, notes and "why I saved this" are kept side by side when they differ, and empty folder, description, website and license are filled.

## Each tool project (SwiftData catalog)

Stored fields you can view and edit:

- Name, short and long description
- GitHub and website links
- Category, license, star count (text)
- Tags and use cases (lists)
- Personal notes
- **Shelf:** Top Shelf (favorites), The Collector (default landing shelf), Yard Sale (not sure / archive). In the list, a row shows its shelf as a small icon on the right, next to the clone icon: Top Shelf a **star**, Yard Sale a **tag** (same symbols and soft colors as the sidebar); The Collector, the default, shows none. The inspector header keeps the colored shelf badge. With a repo selected, move it with **⌘T** (Top Shelf), **⌘Y** (Yard Sale), **⌘⇧G** (The Collector), or the **Shelf** menu / right-click **Move to** — so you can sort straight after capturing without the mouse. ⌘-click adds to the row you already selected, and those shortcuts move the whole batch
- **Local-first** and **self-hosted** flags
- Repo **icon** (fetched and cached)
- **Added** and **last checked** dates

## Sidebar

**Library** — shelf + clone filters

- All Projects, Top Shelf, The Collector, Yard Sale, **Cloned**
- **Cloned** is filesystem-derived (which repos actually have a local clone), filtered in-memory; its count updates live as you clone or remove repos

**Categories** — auto-classified filters, shown **dynamically**: a row appears for every category that actually has repos (with a live count), so nothing is orphaned and new categories show up on their own. Empty categories are hidden.

- Full set: Database, Backend, AI / Agent, Computer Use, MCP, Internal Tools, Workspace, Knowledge, macOS, SwiftUI, CLI, Editor, DevOps, Automation, Media, Security, Utility, Frontend, Games, plus Local-First (flag-based). In 1.15.0 three were merged: Coding Agents into AI / Agent, AI Memory into Knowledge, Design into Frontend; existing repos were renamed and their clone folders moved once, after a backup. A custom clone folder is left where it is. Classification is **rule-based** (GitHub topics → description → language), **no AI** — see `CategoryClassifier`. Repos with no clear signal stay uncategorized (visible under All Projects) rather than being mislabeled with a raw language name. Since 1.3.2 the classifier assigns **SwiftUI** too: SwiftUI component/animation/library repos land there (library-shaped wording like "SwiftUI library" / "for SwiftUI" tips cross-platform packages), while mac *apps* that merely use SwiftUI still land in macOS.

**Collapsible sections** — click the **Folders**, **Categories** or **Tags** heading to fold it away; the choice is remembered.

**Tags** — the last sidebar section: 15 GitHub topics, the cross-cutting view — a repo has one category but many tags, so **swift** finds every Swift repo whatever its category. **Settings → General → Sidebar Tags** picks *Most used* (whole shelf) or *Recently added* (most common among the ~40 newest repos). Noise like open-source/awesome is left out, and spelling twins are merged (menu-bar / menubar). Counts always cover the whole shelf, so a row's number matches what clicking it shows.

**Folders** — a third section between Library and Categories, present only once you have a folder. See [Folders](#folders) below.

**Settings** — opens as a standard macOS **Settings window** from the app menu (**reshelf → Settings…**, ⌘,), not an in-app panel.

## List and search

- **Sort** the list from the header's sort menu (⬆⬇ icon): **Recently Added** (default), **Name (A–Z)**, or **Most Stars** (star strings like `18.2k`/`1.5M` are parsed; ties fall back to name). The choice persists. List header shows the active sidebar filter title
- Active search term shows as a dismissible chip in the header (set from command palette)
- Search: name, descriptions, category, tags, notes, use cases
- **⌘K** — open command palette to search or capture
- Edit from inspector

## Quick Capture

- **⌘N** — sheet to paste a GitHub URL (the old manual "New Project" form was removed in 1.14.0)
- **⌘V** — with a GitHub repo link on the clipboard and no text field focused, opens Quick Capture with it
- **Already shelved** — no fetch; an "Already on your shelf" card, and **Return** jumps to the repo in the list
- Fetches repo info from the **GitHub API** (and can pull README for context)
- **Auto-categorizes** the repo into a meaningful category (Database, AI / Agent, macOS, Workspace, Media, etc.) from its GitHub topics, description, and language — not just the raw language name
- Edit fields, then save into the SwiftData catalog
- **No-mouse flow** — from the command palette (⌘K): paste a URL → **Enter** fetches → **Enter** again saves (Save is the sheet's default button)
- **Capture Assist (on-device)** — on Macs with Apple Intelligence, the AI Suggestions step (behind More Details) fills **use cases, a note, and tags** via guided generation. The note has its own **Notes** field on the form, so you see it before saving; with **auto-generate** on (default) it runs by itself in the background right after save, so the keyboard-only flow is untouched. Fill-only: your typed fields always win

Quick Capture uses a **solid sheet** (readable over any background), not a glass overlay.

Existing projects whose category was empty or just a language name are **re-categorized automatically** on launch, so they land in the right sidebar filter.

## Inspector (detail pane)

- Header, links, shelf
- Metadata, description, use cases, tags, notes
- **No clear license** — rows of repos whose license GitHub reports as none or unclear (NOASSERTION) show a small warning triangle on the right, next to the shelf and clone icons. **Shelf → Move Repos Without a License to Yard Sale…** moves all of them at once (Top Shelf included): it shows the count first, saves a backup, and only changes their shelf — nothing is deleted, clones stay on disk
- **License explainer** — an ⓘ next to the license opens a plain-language popover (what you *can* do, what you *must* do, and the takeaway) for MIT, Apache, BSD, ISC, MPL, LGPL, EPL, GPL, AGPL, EUPL, BUSL, PostgreSQL, CC-BY, WTFPL, public-domain, and more (matched by SPDX id or full name, by whole word); any other license text shows "Unrecognized license: read the LICENSE file" with a caution. When **Warn about strict or missing licenses** is on (Settings), copyleft/source-available repos (GPL, AGPL, MPL, BUSL…) and repos with **no license or an unclear one** (NOASSERTION) also show an automatic caution banner. Plain-language, not legal advice
- **Clickable tags** — click a tag to list every repo that has it
- **Links** — left-click opens GitHub / website in the default browser; right-click copies the URL
- **Local Copy** — a disk icon next to the heading when cloned (orange when updates are waiting), clone status, on-disk path, **Reveal in Finder**, and **Open in…** (installed editors + Terminal); when not cloned, a one-click **Clone Repository**
- Edit sheet
- **Resizable** — drag the divider to set the inspector width (persists)
- **Folder** — the folder a project belongs to, when it's in one (next to Added / Updated)

Extra metadata stays **inside this pane** (no fourth `.inspector()` column).

## Clone & updates (v1, no AI)

Cloning and update-checking are plain `git` — no analysis pipeline, no AI, and no `git-lfs` requirement (LFS smudge/clean filters are bypassed, so LFS repos like `zotero` still clone).

- **Clone Repository** — from the repo's right-click menu or the inspector's Local Copy section. Full clone into the repo's **category subfolder**: `~/reshelf/repos/<Category>/<repo>` (e.g. `~/reshelf/repos/AI Agent/Glyph`), so clones are grouped the same way the catalog is — point an AI agent at one category folder for focused reference. Falls back to `<owner>-<repo>` only on a name collision with a *different* repo. A clone counts only when reshelf made it (a small marker inside `.git`). Clones already in the default folder are marked the first time they're seen. A custom clone folder never treats your own projects as clones, even when a folder is named like one, so Remove Local Clone and Pull leave them alone. Detection scans every category folder, so a clone is still found after you recategorize it. Legacy flat clones are tidied into category folders on launch. Rows show a **spinner while cloning** and a **disk badge** once cloned. Cloning never auto-opens Finder.
- **Update check** — opening a cloned repo's inspector runs a cheap `git ls-remote origin HEAD` (one read-only round-trip, no fetch, no objects downloaded) and shows **✓ Up to date** or **↑ Updates available**. On-demand only — no background polling.
- **Pull** — when behind, a one-click **Pull** brings the clone level with upstream (also when upstream rewrote its history), then flips back to up-to-date. A clone with uncommitted edits or with commits of its own is skipped, never reset. A clone that is only ahead of upstream counts as up to date.
- **Refresh Info** (**Shelf → Refresh Info for Top Shelf / for The Collector**) — re-reads GitHub for every repo on that shelf that is **not cloned**: star count, license and last activity are updated; description and website are filled only when empty; tags, notes, category and shelf are never touched. Progress and a summary (stars and licenses changed, repos no longer on GitHub) show in the list's status line. Repos GitHub answers "not found" for are listed by name with an offer to move them to **Yard Sale** (after a backup, never deleted); nothing moves without a yes, because GitHub also answers "not found" for private repos a token can't see. Cloned repos get the same refresh automatically after each **Pull**. With a GitHub token it takes seconds; without one GitHub allows ~60 requests an hour and the run stops with a note.
- **Check Clones for Updates** (**File** menu, ⌘⇧U) — sweeps every cloned repo at once and flags the ones that are behind with an **orange dot** on their disk badge. Pair it with the **Cloned** sidebar filter to see exactly what needs pulling.
- **git** — clone, check and pull use Apple's Command Line Tools git (a plain message says to run `xcode-select --install` when they're missing). git never waits on a login prompt (private repos fail at once with a plain message), update checks stop after 60 s and pulls after 10 min, and a clone cut off midway doesn't count as cloned. The update check for a selected repo is kept for the session.
- **Remove Local Clone** — right-click a cloned repo → **Remove Local Clone…** (confirm dialog) moves the cloned folder to the **Trash** (recoverable) and removes an emptied category folder. The catalog entry stays; you can clone again anytime. Deleting a clone folder yourself in Finder is also fine — the disk badge and Cloned count notice and update on their own.

reshelf never executes anything on your behalf — clone, pull and update checks are the only git it runs, and a pull never touches edits or commits made in the clone.

## Folders

A **folder** is a grouping you make: "everything I cloned for project X". Deliberately not a category (those are a fixed taxonomy describing *what a repo is*) and not a shelf (that says how much you value it) — a project's worth of repos spans all three shelves and a dozen categories.

- **One folder at most** per project, so "what did I get for X" stays unambiguous.
- **Any project qualifies**, cloned or not. Uncloning must not eject a repo from the group that exists to make the cleanup possible.
- **Pull Repos** — right-click a folder → **Pull Repos** checks only that folder's clones against GitHub and updates the ones behind (clones with local edits are skipped).
- **Assign** — right-click a project → **Add to Folder ▸** lists your folders, marks the one it's in, and offers **New Folder…** and **Remove from Folder**.
- **Sidebar** — folders get their own section between Library and Categories, shown only once one exists. Each row has a folder icon, a live count, and filters the list exactly like a category row.
- **Rename / Delete** — right-click a folder row. **Deleting a folder only ungroups**: its projects keep their shelf, their clone, their notes and everything else. A labelled backup is written first (the same for moving a batch of repos to a shelf). If that backup cannot be written, nothing changes. The confirmation says how many will be ungrouped and that nothing else changes.
- **Inspector** — a **Folder** row appears next to Added / Updated when a project is in one.
- **Travels with the catalog** — folders are written into JSON exports *and* automatic backups. On import they're matched by **name**, case-insensitively, so two Macs that each made a "Photos app" converge on one folder instead of two. A file that carries no folder for a project leaves that project's folder alone.

## Batch actions

Select many rows, then act on all of them — built for the case that motivated folders: ~100 repos cloned for one project that have to be retired together.

- **⌘-click** toggles a row into the selection; **⇧-click** extends from the last plain click; a plain click drops the selection and selects one row.
- The batch is **separate from the inspector's selection**, so assembling one never costs you the detail view of what you were last looking at.
- **Act** — the footer shows "N selected" with an **Actions** menu; right-clicking *inside* the selection gives the same menu. Right-clicking *outside* it acts on that row alone, so a destructive action never lands on rows you weren't pointing at.
- **What you can do** — move them all to a shelf, add them all to a folder, remove their local clones, or remove them from the catalog. Both destructive actions confirm with a count and say what survives: clones go to the Trash and stay in the catalog; catalog removals are backed up first and leave files on disk alone.
- The selection resolves through the **visible list**, so the count can't promise an action over rows that have been filtered away; changing the filter or the search clears it.

## Settings

A fixed 560pt window (reshelf → Settings…, ⌘,), five tabs. Flat rows: the label and one line of help on the left, the control on the right, one hairline between sections.

- **General** — **Theme** (System / Light / Dark, applies to every window), **Sidebar tags** (Most used / Recently added), **License warnings** (inspector caution for copyleft, missing or unclear licenses; the ⓘ explainer is always there)
- **Capture** — **Capture Assist** (on-device Apple Intelligence fill of use cases / note / tags; fill right after each capture; **Fill** for repos without use cases, fill-only) and the optional **GitHub access token** (raises the API limit from ~60 to 5,000 requests/hour, sees private repos; Keychain only, with **Test** / **Remove**)
- **Library** — **Clone folder** (default `~/reshelf/repos`, clones grouped by `<Category>/<repo>`; **Choose…** / **Reset**; only clones reshelf made count, and after a change a note says how many clones stay in the old folder), **Last updated dates** read from clones, the **Agent Skill** install (bundled `reshelf` skill to `~/.claude/skills/reshelf`; an old install is trashed, a symlinked one left alone), and the **Inspector** sections (show/hide, drag to reorder)
- **Guide** — one screen of what is what: the three shelves, the row icons, the main keys, and three steps for using the shelf with an agent
- **About** — app icon, version, one-line description, **Check for Updates…** and automatic checks (Sparkle), "Made by Kika" with three icon-only links (akakika.com, X, GitHub)
- One `AppSettings` row in SwiftData (appearance is stored separately in `@AppStorage`)

## GitHub metadata store

At launch the app also opens a **GRDB SQLite** database (GRDB = a Swift toolkit for SQLite) under `~/reshelf/database/opensource-shelf.sqlite` with tables for:

- **Repositories** — owner, name, URLs, branch, local path, status
- **Repository metadata** — stars, topics, license, language, etc.
- **Clone states** — clone status, path, head, sizes, errors
- **Ingestion jobs** — queued work with status and progress

When a repo is captured or imported, its GitHub metadata is recorded here (`CatalogCaptureIntelligenceService`), and the inspector reads the GitHub topics and description from it. The shelf itself (rows, shelves, folders) is **SwiftData only**; nothing new goes into this database.

## Technical stack

| Piece | Role |
|-------|------|
| SwiftUI | UI |
| SwiftData | Catalog + settings |
| GRDB 7.x | Intelligence SQLite |
| GitHub REST | Quick Capture |
| Apple Intelligence | On-device Capture Assist fills (no key, no cloud) |
| Sparkle | Signed in-app updates from an EdDSA-signed appcast |
