# reshelf

**reshelf** (repo shelf) is a **macOS app** for keeping a personal shelf of open-source repos you might use — with workflow tags, fit scores, and Quick Capture from GitHub.

The menu bar and Dock show the name **reshelf**; the Xcode project folder is still `OpenSourceShelf` for now.

No account. Data stays on your Mac.

> **v1 is the Catalog** — capture, organize, and find open-source repos, zero
> setup. The **Intelligence engine** (clone + AI analysis, runbooks, Compare,
> Ecosystems) is a **v2 preview** hidden behind **Settings → Enable Intelligence**
> (off by default). It needs git and, for the AI steps, a configured provider.

## In one minute

1. Open the project in Xcode (or build from the terminal below).
2. Run the app — you get a **sidebar**, **project list**, and **inspector** pane.
3. Press **⌘K** to open the command palette, paste a GitHub URL — Quick Capture opens with the repo info already fetched and **auto-categorized** (Database, AI / Agent, macOS, …).
4. Mark repos **New → Testing → Useful** (or **Ignored**) and filter by how they fit your work (Codex, local AI, macOS apps, etc.).

Tip: drag the sidebar/inspector dividers to resize them, and in **Settings** show/hide and **drag-reorder** the inspector sections.

Optional (v2 preview): turn on **Settings → Enable Intelligence** to unlock AI suggestions during Quick Capture, plus clone-based stack analysis, runbooks, and Compare.

## How you run it

**Xcode**

1. Open `OpenSourceShelf.xcodeproj`.
2. Select scheme **OpenSource Shelf** (the scheme/target keep the legacy name; the built app is **`reshelf.app`** via `PRODUCT_NAME`).
3. Run (⌘R).

**Terminal**

```bash
# Run from this repository folder (where OpenSourceShelf.xcodeproj lives)

xcodebuild \
  -project OpenSourceShelf.xcodeproj \
  -scheme "OpenSource Shelf" \
  -destination 'platform=macOS' \
  build
```

Built app (Debug) is under DerivedData, or run from Xcode for day-to-day use.

**Requirements:** macOS with Xcode 16+ (Swift 6, SwiftUI, SwiftData). Resolves **GRDB** via Swift Package Manager on first build.

## Where data lives

| What | Where |
|------|--------|
| Catalog UI (projects, settings) | SwiftData — app sandbox |
| Intelligence layer (repos, clone state, jobs) | `~/reshelf/database/opensource-shelf.sqlite` (GRDB) |

The intelligence database is created at launch; the UI catalog is still the main surface today. See [features.md](features.md) and [future-features.md](future-features.md) for what is wired vs planned.

## Project docs

| File | Purpose |
|------|---------|
| [goals.md](goals.md) | Why the app exists and product principles |
| [features.md](features.md) | What works today |
| [future-features.md](future-features.md) | Ideas not built yet |
| [todo.md](todo.md) | Near-term checklist |
| [AGENTS.md](AGENTS.md) | Rules for humans and coding agents |

## Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘K | Command palette — search projects or paste a GitHub URL |
| ⌘N | New project (manual) |
| ⌘⇧N | Quick Capture (GitHub URL) |
| ⌘S | Toggle sidebar |
| ⌘I | Toggle inspector |

## Privacy and network

- **GitHub API** — only when you use Quick Capture (repo metadata, optional README).
- **Ollama** — only if enabled in Settings; talks to your local Ollama URL (default `http://localhost:11434`).
- No sign-in, no required cloud sync.

## Stack (plain terms)

- **SwiftUI** — interface
- **SwiftData** — shelf entries you see in the app
- **GRDB (SQLite)** — deeper “intelligence” store for repos, metadata, clone state, and ingestion jobs (foundation for future analysis)
- **GitHub REST** + **Ollama HTTP** — optional helpers
