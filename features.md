# Features

What **reshelf** does today. Plain-language map of the app — see [README.md](README.md) to run it.

## Main window (what you use daily)

- **Three columns** — sidebar (owl app-icon branding), project list (title + controls header), inspector pane. The sidebar and inspector are **user-resizable** by dragging their dividers; the project list flexes between them.
- **Merged title bar** — the header row doubles as the window title bar (no separate empty toolbar band). The controls live in the project-list header: a **sidebar toggle** on the left, **search** (⌘K) and **inspector toggle** on the right. Toggles stay visible even when their panel is collapsed, so you can always reopen it. The three column header dividers line up as one clean line, and the sidebar edge is a thin hairline (not a heavy macOS shadow).
- **Command palette** (⌘K) — floating sheet with search field, recent searches, live project filtering. Paste a GitHub URL → "Capture this repository" row appears → click or press Enter → Quick Capture opens with repo info auto-fetched. Escape dismisses.
- **Menu bar** — File (New / Quick Capture / Search / Export / Import / Restore / **Check Clones for Updates** ⌘⇧U), View (column toggles + navigation), and the app menu (Settings, About). The intelligence menus (Catalog, Actions, Window → Queue) appear only with **Labs on**. No status-bar menu extra.
- **No sign-in** — local app only.
- **Seed library** — on first empty launch, sample tools (Baserow, NocoDB, AppFlowy, Budibase, etc.) are inserted once.

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

- Full set: Database, Backend, AI / Agent, Internal Tools, Workspace, Knowledge, macOS, CLI, Editor, DevOps, Automation, Media, Design, Security, Utility, plus Local-First (flag-based). Classification is **rule-based** (GitHub topics → description → language), **no AI** — see `CategoryClassifier`. Repos with no clear signal stay uncategorized (visible under All Projects) rather than being mislabeled with a raw language name.

**Intelligence (v2 preview)** (Settings → **Enable Intelligence**, off by default) — the entire intelligence engine is gated behind one flag. With it **off** (the v1 default), reshelf is a pure catalog: no clone/Fetch-Intelligence, no runbooks, no Compare/Ecosystems, no Queue or Actions menu, no AI step in Quick Capture, no AI-Providers or Repository-Storage settings, and no intelligence badges on rows or in the inspector. Turning it **on** restores all of it unchanged (clone + AI analysis, runbooks, Compare, Ecosystems, Workflows, My Stack, Queue, AI providers, clone-folder setting).

**Intelligence surfaces** (View and Window menus when Labs is on, not sidebar) — Compare (⌘⇧C), Ecosystems, Workflows, My Stack. Window → Explore also lists the three discovery views. Selecting a cluster shows detail in the inspector; repo rows jump back to the catalog when linked.

**Compare** — the main area toggles between a **repo picker** (selection mode) and the **results view**; running a comparison flips to results, "Edit Repos" returns to the picker. Results lead with a winner hero card, ranking cards with score bars, and the comparison matrix (winner column highlighted), followed by the decision summary and detail cards. The inspector is a per-repo deep dive that defaults to the winner and follows ranking clicks.

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
- Under **Labs**, the configured AI provider (Settings → AI) can be used instead — Ollama locally, Apple Intelligence, or OpenAI, Anthropic, Gemini, GitHub Models with an API key

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
- **Discovery clusters** — when viewing Ecosystems, Workflows, or My Stack (View/Window menu, Labs on), select a cluster to inspect score, stack, and gaps; tap a repo to open it in the catalog

Extra metadata stays **inside this pane** (no fourth `.inspector()` column).

## Clone & updates (v1, no AI)

Cloning and update-checking are plain `git` — no analysis pipeline, no AI, and no `git-lfs` requirement (LFS smudge/clean filters are bypassed, so LFS repos like `zotero` still clone).

- **Clone Repository** — from the repo's right-click menu or the inspector's Local Copy section. Full clone into the repo's **category subfolder**: `~/reshelf/repos/<Category>/<repo>` (e.g. `~/reshelf/repos/AI Agent/Glyph`), so clones are grouped the same way the catalog is — point an AI agent at one category folder for focused reference. Falls back to `<owner>-<repo>` only on a name collision with a *different* repo. Detection scans every category folder, so a clone is still found after you recategorize it. Legacy flat clones are tidied into category folders on launch. Rows show a **spinner while cloning** and a **disk badge** once cloned. Cloning never auto-opens Finder.
- **Update check** — opening a cloned repo's inspector runs a cheap `git ls-remote origin HEAD` (one read-only round-trip, no fetch, no objects downloaded) and shows **✓ Up to date** or **↑ Updates available**. On-demand only — no background polling.
- **Pull** — when behind, a one-click **Pull** does a fast-forward pull, then flips back to up-to-date.
- **Check Clones for Updates** (**File** menu, ⌘⇧U) — sweeps every cloned repo at once and flags the ones that are behind with an **orange dot** on their disk badge. Pair it with the **Cloned** sidebar filter to see exactly what needs pulling.
- **Remove Local Clone** — right-click a cloned repo → **Remove Local Clone…** (confirm dialog) moves the cloned folder to the **Trash** (recoverable) and removes an emptied category folder. The catalog entry stays; you can clone again anytime. Deleting a clone folder yourself in Finder is also fine — the disk badge and Cloned count notice and update on their own.

## Runbooks

- **Generate** from the inspector or Actions menu — stored in the intelligence database, not written into the clone automatically
- **Open Runbook** opens a dedicated read-only window (rendered Markdown, raw toggle, copy/export)
- **Save to Clone Folder** (in the runbook window) writes `RESHELF-RUNBOOK.md` beside the local clone when one exists
- reshelf never executes suggested commands — review before running anything in Terminal

## Settings

- **Appearance** — System / Light / Dark (System follows macOS); applies to every window and persists
- **Warn about strict licenses** — when on (default), the inspector auto-shows a caution for copyleft/source-available licenses (GPL, AGPL, MPL, LGPL, BUSL…); the ⓘ license explainer is always available regardless
- **Capture Assist** — the on-device Apple Intelligence fill (use cases / note / tags): master toggle, live model-availability status, **auto-generate on every capture** (default on), and **Fill Missing Entries** to backfill shelved entries that have none (fill-only, hand-edited data untouched)
- **Agent Skill** — one-click install of the bundled `reshelf` Claude Code skill to `~/.claude/skills/reshelf` (a previous install is trashed, not deleted)
- **Repository storage** — choose the folder where repos are cloned (folder picker); defaults to `~/reshelf/repos`. Clones are grouped into **category subfolders** (`<Category>/<repo>`, or `<owner>-<repo>` on a name collision). Changing it affects only new clones; **Reset** returns to the default
- **AI Providers** (Labs) — pick a **preferred provider** for suggestions; configure **Ollama** (local URL + model), **Apple Intelligence** (on-device, live availability), **OpenAI**, **Anthropic**, **Gemini**, and **GitHub Copilot / Models** (API keys stored in Keychain, model picker, connection test)
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
| Ollama / cloud AI APIs | Optional AI suggestions (local-first; cloud opt-in) |
