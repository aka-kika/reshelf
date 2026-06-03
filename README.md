# reshelf

**reshelf** (repo shelf) is a **macOS app** for keeping a personal shelf of open-source repos you might use — capture from GitHub, organize onto shelves, clone locally, and get told when a clone has updates to pull.

The menu bar and Dock show the name **reshelf**; the Xcode project folder is still `OpenSourceShelf` for now.

No account. Data stays on your Mac.

![platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![license: MIT](https://img.shields.io/badge/license-MIT-green) ![status: v1 testing](https://img.shields.io/badge/status-v1%20testing-yellow)

> **Status:** v1 is in early testing. Things may change and break. Bug reports and
> contributions are very welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

> **v1 is the Catalog** — capture, organize, and find open-source repos, zero
> setup. The **Intelligence engine** (clone + AI analysis, runbooks, Compare,
> Ecosystems) is a **v2 preview** hidden behind **Settings → Enable Intelligence**
> (off by default). It needs git and, for the AI steps, a configured provider.

## In one minute

1. Open the project in Xcode (or build from the terminal below).
2. Run the app — you get a **sidebar**, **project list**, and **inspector** pane.
3. Press **⌘K** to open the command palette, paste a GitHub URL — Quick Capture opens with the repo info already fetched and **auto-categorized** (Database, AI / Agent, macOS, …).
4. Sort repos onto shelves — **Top Shelf** (favorites), **The Collector** (default landing shelf), **Yard Sale** (not sure / archive) — and filter the sidebar by shelf, category, or **Cloned**.
5. Right-click a repo → **Clone Repository** to pull a full copy to `~/reshelf/repos`. The inspector shows whether a clone is **up to date** or has **updates available** with a one-click **Pull**; **File → Check Clones for Updates** (⌘⇧U) sweeps every clone at once.

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
| Catalog (projects, settings) | `~/reshelf/catalog.store` (SwiftData — isolated, not the shared default store) |
| Automatic JSON backups | `~/reshelf/backups/` (last 30 add/remove/background snapshots) |
| Local clones | `~/reshelf/repos/<repo>` (flat by repo name; full clones) |
| Intelligence layer (v2 preview) | `~/reshelf/database/opensource-shelf.sqlite` (GRDB) |

The intelligence database is created at launch; the v1 catalog is the main surface today. See [features.md](features.md) and [future-features.md](future-features.md) for what is wired vs planned.

## Project docs

| File | Purpose |
|------|---------|
| [goals.md](goals.md) | Why the app exists and product principles |
| [features.md](features.md) | What works today |
| [future-features.md](future-features.md) | Ideas not built yet |
| [todo.md](todo.md) | Near-term checklist |
| [v2.0-roadmap.md](v2.0-roadmap.md) | What's next (GitHub login is first up) |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to build and contribute |
| [AGENTS.md](AGENTS.md) | Rules for humans and coding agents |

## Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘K | Command palette — search projects or paste a GitHub URL |
| ⌘N | New project (manual) |
| ⌘⇧N | Quick Capture (GitHub URL) |
| ⌘⇧E | Export catalog as JSON |
| ⌘⇧U | Check clones for updates |
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

## Contributing

reshelf is open to contributions — bug reports, fixes, features, docs, and design
feedback. Start with [CONTRIBUTING.md](CONTRIBUTING.md) for build steps and the
one important gotcha (new Swift files must be registered in `project.pbxproj`).
Use the issue templates for bugs and feature requests.

## Roadmap

v1 is **the Catalog**. Next up is **GitHub login inside the app** (read-only,
token in Keychain) to power better recommendations — see
[v2.0-roadmap.md](v2.0-roadmap.md).

## License

[MIT](LICENSE) © reshelf contributors.
