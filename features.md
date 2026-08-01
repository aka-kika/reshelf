# Features

What **reshelf** does today. Plain-language map of the app — see [README.md](README.md) to run it.

## Main window (what you use daily)

- **Three columns** — sidebar (owl app-icon branding), project list (title + controls header), inspector pane. The sidebar and inspector are **user-resizable** by dragging their dividers; the project list flexes between them.
- **Merged title bar** — the header row doubles as the window title bar (no separate empty toolbar band). The controls live in the project-list header: a **sidebar toggle** on the left, **search** (⌘K) and **inspector toggle** on the right. Toggles stay visible even when their panel is collapsed, so you can always reopen it. The three column header dividers line up as one clean line, and the sidebar edge is a thin hairline (not a heavy macOS shadow).
- **Command palette** (⌘K) — floating sheet with search field, recent searches, live project filtering. Paste a GitHub URL → "Capture this repository" row appears → click or press Enter → Quick Capture opens with repo info auto-fetched. Escape dismisses.
- **Menu bar** — File (New / Quick Capture / Search / Export / Import / Restore / **Check Clones for Updates** ⌘⇧U), View (column toggles + navigation), and the app menu (Settings, About, Check for Updates). No status-bar menu extra.
- **No sign-in** — local app only.
- **Seed library** — on first empty launch, nine repos worth having are inserted once (jade, Seedling, kika-obsidian-mcp, ollama, Handy, zed, excalidraw, lazygit, immich). Only ever when there is nothing to show.

## Data safety

- **Isolated store** — the SwiftData catalog lives at `~/reshelf/catalog.store` (next to the intelligence DB), not the shared `~/Library/Application Support/default.store`. A non-sandboxed app sharing the default store risks a destructive reset from any other SwiftData app or schema-divergent build.
- **Automatic backups** — every add/remove and every time the app backgrounds, a full-fidelity JSON snapshot is written to `~/reshelf/backups/` (last 30 kept). Same schema as **File → Export Catalog as JSON…** (⌘⇧E), so backups and exports are interchangeable.
- **Auto-restore-on-empty** — on launch, if the catalog is empty but a backup with data exists, it restores from the backup instead of seeding defaults (so a transient empty state can't silently destroy a real catalog).
- **Manual recovery** — **File → Restore from Backup…** lists snapshots (date + count) and merges a chosen one in non-destructively. **File → Import GitHub URLs…** bulk-adds a pasted list of repos (also the path to rebuild from a recovered URL list).
- **No duplicates** — capture (Quick Capture, Add Project, Import URLs) detects when a repo is already in the catalog by normalized `owner/repo` (so `https`/`www.`/trailing slash/`.git`/case all match) and blocks the save with an "already in your catalog" notice. **File → Remove Duplicate Repos…** cleans up any pre-existing duplicates, keeping the best-filled copy of each (higher shelf, richer/edited data, then the original) and saving a backup first.

## Each tool project (SwiftData catalog)

Stored fields you can view and edit:

- Name, short and long description
- GitHub and website links
- Category, license, star count (text)
- Tags and use cases (lists)
- Personal notes and **fit score** (1–5 stars)
- **Shelf:** Top Shelf (favorites), The Collector (default landing shelf), Yard Sale (not sure / archive). Color-coded badges — Top Shelf **blue** (keeper), The Collector **gray** (neutral), Yard Sale **amber** (needs review). With a repo selected, move it with **⌘T** (Top Shelf), **⌘Y** (Yard Sale), **⌘⇧G** (The Collector), or the **Shelf** menu / right-click **Move to** — so you can sort straight after capturing without the mouse
- **Local-first** and **self-hosted** flags
- Repo **icon** (fetched and cached)
- **Added** and **last checked** dates

## Sidebar

**Library** — shelf + clone filters

- All Projects, Top Shelf, The Collector, Yard Sale, **Cloned**
- **Cloned** is filesystem-derived (which repos actually have a local clone), filtered in-memory; its count updates live as you clone or remove repos

**Categories** — auto-classified filters, shown **dynamically**: a row appears for every category that actually has repos (with a live count), so nothing is orphaned and new categories show up on their own. Empty categories are hidden.

- Full set: Database, Backend, AI / Agent, Coding Agents, Computer Use, AI Memory, MCP, Internal Tools, Workspace, Knowledge, macOS, SwiftUI, CLI, Editor, DevOps, Automation, Media, Design, Security, Utility, Frontend, Games, plus Local-First (flag-based). Classification is **rule-based** (GitHub topics → description → language), **no AI** — see `CategoryClassifier`. Repos with no clear signal stay uncategorized (visible under All Projects) rather than being mislabeled with a raw language name. Since 1.3.2 the classifier assigns **SwiftUI** too: SwiftUI component/animation/library repos land there (library-shaped wording like "SwiftUI library" / "for SwiftUI" tips cross-platform packages), while mac *apps* that merely use SwiftUI still land in macOS.

**Folders** — a third section between Library and Categories, present only once you have a folder. See [Folders](#folders) below.

**Settings** — opens as a standard macOS **Settings window** from the app menu (**reshelf → Settings…**, ⌘,), not an in-app panel.

## List and search

- **Sort** the list from the header's sort menu (⬆⬇ icon): **Recently Added** (default), **Name (A–Z)**, or **Most Stars** (star strings like `18.2k`/`1.5M` are parsed; ties fall back to name). The choice persists. List header shows the active sidebar filter title
- Active search term shows as a dismissible chip in the header (set from command palette)
- Search: name, descriptions, category, tags, notes, use cases
- **⌘K** — open command palette to search or capture
- **⌘N** — add project manually
- Edit from inspector

## Quick Capture

- **⌘⇧N** — sheet to paste a GitHub URL
- Fetches repo info from the **GitHub API** (and can pull README for context)
- **Auto-categorizes** the repo into a meaningful category (Database, AI / Agent, macOS, Workspace, Media, etc.) from its GitHub topics, description, and language — not just the raw language name
- Edit fields, then save into the SwiftData catalog
- **No-mouse flow** — from the command palette (⌘K): paste a URL → **Enter** fetches → **Enter** again saves (Save is the sheet's default button)
- **Capture Assist (on-device)** — on Macs with Apple Intelligence, the AI Suggestions step (behind More Details) fills **use cases, a note, and tags** via guided generation; with **auto-generate** on (default) it runs by itself in the background right after save, so the keyboard-only flow is untouched. Fill-only: your typed fields always win

Quick Capture uses a **solid sheet** (readable over any background), not a glass overlay.

Existing projects whose category was empty or just a language name are **re-categorized automatically** on launch, so they land in the right sidebar filter.

## Inspector (detail pane)

- Header, links, shelf
- Metadata, description, use cases, tags, notes
- **License explainer** — an ⓘ next to the license opens a plain-language popover (what you *can* do, what you *must* do, and the takeaway) for MIT, Apache, BSD, ISC, MPL, LGPL, EPL, GPL, AGPL, BUSL, public-domain, and more. When **Warn about strict licenses** is on (Settings), copyleft/source-available repos (GPL, AGPL, MPL, BUSL…) also show an automatic caution banner. Plain-language, not legal advice
- Personal fit
- **Links** — left-click opens GitHub / website in the default browser; right-click copies the URL
- **Local Copy** — clone status, on-disk path, **Reveal in Finder**, and **Open in…** (installed editors + Terminal); when not cloned, a one-click **Clone Repository**
- Edit sheet
- **Resizable** — drag the divider to set the inspector width (persists)
- **Folder** — the folder a project belongs to, when it's in one (next to Added / Updated)

Extra metadata stays **inside this pane** (no fourth `.inspector()` column).

## Clone & updates (v1, no AI)

Cloning and update-checking are plain `git` — no analysis pipeline, no AI, and no `git-lfs` requirement (LFS smudge/clean filters are bypassed, so LFS repos like `zotero` still clone).

- **Clone Repository** — from the repo's right-click menu or the inspector's Local Copy section. Full clone into the repo's **category subfolder**: `~/reshelf/repos/<Category>/<repo>` (e.g. `~/reshelf/repos/AI Agent/Glyph`), so clones are grouped the same way the catalog is — point an AI agent at one category folder for focused reference. Falls back to `<owner>-<repo>` only on a name collision with a *different* repo. Detection scans every category folder, so a clone is still found after you recategorize it. Legacy flat clones are tidied into category folders on launch. Rows show a **spinner while cloning** and a **disk badge** once cloned. Cloning never auto-opens Finder.
- **Update check** — opening a cloned repo's inspector runs a cheap `git ls-remote origin HEAD` (one read-only round-trip, no fetch, no objects downloaded) and shows **✓ Up to date** or **↑ Updates available**. On-demand only — no background polling.
- **Pull** — when behind, a one-click **Pull** does a fast-forward pull, then flips back to up-to-date.
- **Check Clones for Updates** (**File** menu, ⌘⇧U) — sweeps every cloned repo at once and flags the ones that are behind with an **orange dot** on their disk badge. Pair it with the **Cloned** sidebar filter to see exactly what needs pulling.
- **Remove Local Clone** — right-click a cloned repo → **Remove Local Clone…** (confirm dialog) moves the cloned folder to the **Trash** (recoverable) and removes an emptied category folder. The catalog entry stays; you can clone again anytime. Deleting a clone folder yourself in Finder is also fine — the disk badge and Cloned count notice and update on their own.

reshelf never executes anything on your behalf — clone, pull and update checks are the only git it runs, all read-only or fast-forward.

## Folders

A **folder** is a grouping you make: "everything I cloned for project X". Deliberately not a category (those are a fixed taxonomy describing *what a repo is*) and not a shelf (that says how much you value it) — a project's worth of repos spans all three shelves and a dozen categories.

- **One folder at most** per project, so "what did I get for X" stays unambiguous.
- **Any project qualifies**, cloned or not. Uncloning must not eject a repo from the group that exists to make the cleanup possible.
- **Assign** — right-click a project → **Add to Folder ▸** lists your folders, marks the one it's in, and offers **New Folder…** and **Remove from Folder**.
- **Sidebar** — folders get their own section between Library and Categories, shown only once one exists. Each row has a folder icon, a live count, and filters the list exactly like a category row.
- **Rename / Delete** — right-click a folder row. **Deleting a folder only ungroups**: its projects keep their shelf, their clone, their notes and everything else. The confirmation says how many will be ungrouped and that nothing else changes.
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

- **Appearance** — System / Light / Dark (System follows macOS); applies to every window and persists
- **Warn about strict licenses** — when on (default), the inspector auto-shows a caution for copyleft/source-available licenses (GPL, AGPL, MPL, LGPL, BUSL…); the ⓘ license explainer is always available regardless
- **Capture Assist** — the on-device Apple Intelligence fill (use cases / note / tags): master toggle, live model-availability status, **auto-generate on every capture** (default on), and **Fill Missing Entries** to backfill shelved entries that have none (fill-only, hand-edited data untouched)
- **GitHub token** (optional) — paste a personal access token to raise the API rate limit from ~60 to 5,000 requests/hour (and let Quick Capture see your private repos). Stored in the macOS Keychain only; saving verifies it against GitHub immediately, with **Test** and **Remove** on hand
- **Agent Skill** — one-click install of the bundled `reshelf` Claude Code skill to `~/.claude/skills/reshelf` (a previous install is trashed, not deleted)
- **Repository storage** — choose the folder where repos are cloned (folder picker); defaults to `~/reshelf/repos`. Clones are grouped into **category subfolders** (`<Category>/<repo>`, or `<owner>-<repo>` on a name collision). Changing it affects only new clones; **Reset** returns to the default
- **Software Update** — automatic update checks on/off (Sparkle), plus **Check for Updates…** on demand. Updates are EdDSA-signed and notarized; the feed is a static file on GitHub Pages
- **Inspector sections** — show/hide each section **and drag to reorder** them; both visibility and order persist and drive how the inspector renders
- **About** — app icon, version, tagline, and links (akakika.com, GitHub, X)
- One `AppSettings` row in SwiftData (appearance is stored separately in `@AppStorage`)

## Intelligence database (foundation, not in UI yet)

At launch the app also opens a **GRDB SQLite** database under `~/reshelf/database/opensource-shelf.sqlite` with tables for:

- **Repositories** — owner, name, URLs, branch, local path, status
- **Repository metadata** — stars, topics, license, language, etc.
- **Clone states** — clone status, path, head, sizes, errors
- **Ingestion jobs** — queued work with status and progress

This layer is initialized and has a **smoke test** API in code; the shelf UI still uses **SwiftData only**. Bridging catalog ↔ intelligence is planned — see [future-features.md](future-features.md).

## Technical stack

| Piece | Role |
|-------|------|
| SwiftUI | UI |
| SwiftData | Catalog + settings |
| GRDB 7.x | Intelligence SQLite |
| GitHub REST | Quick Capture |
| Apple Intelligence | On-device Capture Assist fills (no key, no cloud) |
| Sparkle | Signed in-app updates from an EdDSA-signed appcast |
