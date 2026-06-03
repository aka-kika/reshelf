# Changelog

All notable changes to **reshelf** are documented here. This project follows
[Semantic Versioning](https://semver.org/) loosely while pre-1.0.

## [Unreleased]

### Planned (v2 — first up after v1 testing)
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

### Notes
- The **Intelligence engine** (clone + AI analysis, runbooks, Compare,
  Ecosystems) is a **v2 preview** behind **Settings → Enable Intelligence**
  (off by default). No engine code is removed; it's dormant for v1.
