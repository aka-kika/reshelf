# Changelog

All notable changes to **reshelf** are documented here. This project follows
[Semantic Versioning](https://semver.org/) loosely while pre-1.0.

## [Unreleased]

### Added
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

### Fixed
- App icon rendered generic — regenerated a complete `.icns` (all sizes).
- Clicking felt slow — the clone lookup is now a cached index (O(1)), not a
  filesystem walk per row.
- The "updates available" row dot now clears immediately after a pull.

### Planned (v2 — first up)
- **GitHub login inside the app** — connect your GitHub account (read-only) to
  improve recommendations and personal-fit. See [v2.0-roadmap.md](v2.0-roadmap.md).

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
