# Features

What **reshelf** does today. Plain-language map of the app — see [README.md](README.md) to run it.

## Main window (what you use daily)

- **Three columns** — sidebar (owl app-icon branding), project list (title + controls header), inspector pane. The sidebar and inspector are **user-resizable** by dragging their dividers; the project list flexes between them.
- **Merged title bar** — the header row doubles as the window title bar (no separate empty toolbar band). The controls live in the project-list header: a **sidebar toggle** on the left, **search** (⌘K) and **inspector toggle** on the right. Toggles stay visible even when their panel is collapsed, so you can always reopen it. The three column header dividers line up as one clean line, and the sidebar edge is a thin hairline (not a heavy macOS shadow).
- **Command palette** (⌘K) — floating sheet with search field, recent searches, live project filtering. Paste a GitHub URL → "Capture this repository" row appears → click or press Enter → Quick Capture opens with repo info auto-fetched. Escape dismisses.
- **Menu bar** — File (New / Quick Capture / Search), View (column toggles + navigation), Catalog (runbook filter, fetch intelligence, compare flow), Actions (runbook + intelligence), and Window (Show Queue, ⌘⇧Q). No status-bar menu extra.
- **No sign-in** — local app only.
- **Seed library** — on first empty launch, sample tools (Baserow, NocoDB, AppFlowy, Budibase, etc.) are inserted once.

## Data safety

- **Isolated store** — the SwiftData catalog lives at `~/reshelf/catalog.store` (next to the intelligence DB), not the shared `~/Library/Application Support/default.store`. A non-sandboxed app sharing the default store risks a destructive reset from any other SwiftData app or schema-divergent build.
- **Automatic backups** — every add/remove and every time the app backgrounds, a full-fidelity JSON snapshot is written to `~/reshelf/backups/` (last 30 kept). Same schema as **File → Export Catalog as JSON…** (⌘⇧E), so backups and exports are interchangeable.
- **Auto-restore-on-empty** — on launch, if the catalog is empty but a backup with data exists, it restores from the backup instead of seeding defaults (so a transient empty state can't silently destroy a real catalog).
- **Manual recovery** — **File → Restore from Backup…** lists snapshots (date + count) and merges a chosen one in non-destructively. **File → Import GitHub URLs…** bulk-adds a pasted list of repos (also the path to rebuild from a recovered URL list).

## Each tool project (SwiftData catalog)

Stored fields you can view and edit:

- Name, short and long description
- GitHub and website links
- Category, license, star count (text)
- Tags and use cases (lists)
- Personal notes and **fit score** (1–5 stars)
- **Status:** New, Testing, Useful, Ignored
- **Workflow flags:** helps Codex, local AI, macOS apps, content/design, private projects
- **Local-first** and **self-hosted** toggles
- Repo **icon** (fetched and cached)
- **Added** and **last checked** dates

## Sidebar

**Library** — status filters

- All Projects, Useful for Me, Testing, Ignored

**Categories** — top auto-classified filters in the sidebar (full taxonomy in `CategoryClassifier`)

- Database Tools, Agent Tools, macOS Tools, Workspace, Knowledge, CLI, DevOps, Editor, Local-First

**My Workflows** — personal workflow lanes (catalog flags + manual pins)

- Codex Workflow, Local AI Stack, Private Projects
- **Pinned** — add public GitHub repos or local project folders per lane (header **Add Repo** / **Add Folder**); pins show above catalog matches
- **From Catalog** — projects tagged with the workflow toggles in the inspector / edit sheet
- **Deduped display** — repo pins hide when the same GitHub URL already exists in the catalog for that lane; **Add to Catalog** on a pin creates the catalog row and removes the pin

**Intelligence (v2 preview)** (Settings → **Enable Intelligence**, off by default) — the entire intelligence engine is gated behind one flag. With it **off** (the v1 default), reshelf is a pure catalog: no clone/Fetch-Intelligence, no runbooks, no Compare/Ecosystems, no Queue or Actions menu, no AI step in Quick Capture, no AI-Providers or Repository-Storage settings, and no intelligence badges on rows or in the inspector. Turning it **on** restores all of it unchanged (clone + AI analysis, runbooks, Compare, Ecosystems, Workflows, My Stack, Queue, AI providers, clone-folder setting).

**Intelligence surfaces** (View and Window menus when Labs is on, not sidebar) — Compare (⌘⇧C), Ecosystems, Workflows, My Stack. Window → Explore also lists the three discovery views. Selecting a cluster shows detail in the inspector; repo rows jump back to the catalog when linked.

**Compare** — the main area toggles between a **repo picker** (selection mode) and the **results view**; running a comparison flips to results, "Edit Repos" returns to the picker. Results lead with a winner hero card, ranking cards with score bars, and the comparison matrix (winner column highlighted), followed by the decision summary and detail cards. The inspector is a per-repo deep dive that defaults to the winner and follows ranking clicks.

**Settings** — opens as a standard macOS **Settings window** from the app menu (**reshelf → Settings…**, ⌘,), not an in-app panel.

## List and search

- Projects sorted by name; list header shows the active sidebar filter title
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
- **Your configured AI provider** (Settings → AI Providers) can suggest notes / use cases — Ollama locally, or OpenAI, Anthropic, Gemini, GitHub Models when enabled with an API key

Quick Capture uses a **solid sheet** (readable over any background), not a glass overlay.

Existing projects whose category was empty or just a language name are **re-categorized automatically** on launch, so they land in the right sidebar filter.

## Inspector (detail pane)

- Header, links, status
- Metadata, description, use cases, tags, notes
- Personal fit and workflow toggles
- Open GitHub / website in the default browser
- Edit sheet
- **Resizable** — drag the divider to set the inspector width (persists)
- **Discovery clusters** — when viewing Ecosystems, Workflows, or My Stack (View/Window menu), select a cluster to inspect score, stack, and gaps; tap a repo to open it in the catalog

Extra metadata stays **inside this pane** (no fourth `.inspector()` column).

## Runbooks

- **Generate** from the inspector or Actions menu — stored in the intelligence database, not written into the clone automatically
- **Open Runbook** opens a dedicated read-only window (rendered Markdown, raw toggle, copy/export)
- **Save to Clone Folder** (in the runbook window) writes `RESHELF-RUNBOOK.md` beside the local clone when one exists
- reshelf never executes suggested commands — review before running anything in Terminal

## Settings

- **Appearance** — System / Light / Dark (System follows macOS); applies to every window and persists
- **Repository storage** — choose the folder where repos are cloned (folder picker); defaults to `~/reshelf/repos`. Repos are organized by host/owner/name inside it. Changing it affects only new clones; **Reset** returns to the default
- **AI Providers** — pick a **preferred provider** for suggestions; configure **Ollama** (local URL + model), **OpenAI**, **Anthropic**, **Gemini**, and **GitHub Copilot / Models** (API keys stored in Keychain, model picker, connection test). **Apple Intelligence** toggle remains placeholder until wired.
- **Inspector sections** — show/hide each section **and drag to reorder** them; both visibility and order persist and drive how the inspector renders
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
