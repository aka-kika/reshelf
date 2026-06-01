# Future features

Ideas **not** in the UI yet. Filename kept as `future-features.md` for your earlier naming. Prioritized with [AGENTS.md](AGENTS.md): main window stable before palette/menu bar.

## Intelligence layer (GRDB — highest leverage)

- [ ] **Bridge SwiftData ↔ GRDB** — Quick Capture writes `RepositoryRecord` + metadata; shelf shows one source of truth
- [ ] **Ingestion job runner** — process queue: fetch metadata, README, license refresh
- [ ] **Clone state UI** — show local path, last fetch, errors per repo
- [ ] **Dedupe by `github_url`** across catalog and intelligence tables
- [ ] **Sync status** — map SwiftData `ProjectStatus` ↔ intelligence `user_status`

## Capture and data

- [ ] Non-GitHub hosts (GitLab, Codeberg) + manual homepage capture
- [ ] Drag URL to Dock icon → Quick Capture
- [ ] Clipboard watcher for `github.com` links
- [ ] User-controlled periodic GitHub refresh (rate-limited)
- [ ] Import / export JSON for full shelf + intelligence backup

## AI and intelligence

- [ ] **Apple Intelligence** — on-device summaries when Foundation Models are wired (or hide toggle until then)
- [ ] Structured AI: suggested fit score + workflow flags from README
- [ ] Batch Ollama pass over all **New** projects
- [ ] Compare two projects for one workflow

## Navigation and UX (after main window is solid)

- [ ] **Command palette (⌘K)** — Raycast-style: jump project, set status, open GitHub; **opaque** panel
- [ ] Menu bar extra for Quick Capture without raising main window
- [ ] Settings: **hide inspector sections** (metadata, use cases, tags, etc.)
- [ ] List density toggle; pinned / recent row
- [ ] Empty states for every sidebar filter and zero search results

## Organization

- [ ] Custom smart collections beyond fixed sidebar items
- [ ] Multiple fit dimensions (docs, maintenance, build quality)
- [ ] Related projects (“alternative to X”)
- [ ] “Not checked in 90 days” view using `lastCheckedDate`

## Integrations

- [ ] **GitHub workflow connection (v2.0)** — optional connect for stars/owned repos → workflow profile → smarter recommendations. **Deferred** — spec in [v2.0-roadmap.md](v2.0-roadmap.md); not in current builds.
- [ ] Open in Cursor / VS Code when `local_path` is set
- [ ] Obsidian export (one note per repo)
- [ ] Optional Pieces / workstream log when marking Useful
- [ ] UNDRDR / repo graph export for high-fit tools

## Distribution

- [ ] Public repo README + screenshots (partially done — maintain with releases)
- [ ] Signed, notarized `.dmg`
- [ ] Sparkle updates (if outside Mac App Store)

## Quality

- [ ] Unit tests: GitHub URL parse, API mapping, GRDB migrations, sidebar predicates
- [ ] UI smoke tests: capture, filter, search
- [ ] Swift 6 concurrency audit on services
- [ ] Accessibility: VoiceOver on list + inspector
- [ ] `.gitignore` for `.build/` and SPM checkouts

## Explicitly later (per goals)

- Team sync, cloud accounts, in-app `git clone`
