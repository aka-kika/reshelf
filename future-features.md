# Future features

Ideas **not** built yet — a backlog, not a commitment. The headline next item
(in-app **GitHub login**) has its own spec in [v2.0-roadmap.md](v2.0-roadmap.md).

## Capture & data

- [ ] Non-GitHub hosts (GitLab, Codeberg) + manual homepage-only capture
- [ ] Clipboard watcher / drag-URL-to-Dock → Quick Capture without raising the window
      (in-app half shipped in 1.11.0: ⌘V with a GitHub link opens Quick Capture)
- [ ] User-controlled periodic GitHub metadata refresh (rate-limited)
- [ ] "Not checked in 90 days" view using `lastCheckedDate`

## Organization

- [x] ~~Folders for clones (sidebar tree) and multi-select + batch actions~~ — shipped in 1.9.0.
- [ ] Custom smart collections beyond the built-in sidebar filters
- [ ] Manual category override when the auto-classifier guesses wrong
- [x] ~~**"Last updated" as first-class metadata + a sort option**~~ — shipped in
      1.6.0 (2026-07-27): `lastUpdatedDate` on `ToolProject`, a **Recently Updated**
      sort, and a Settings action that backfills from each clone's own git log —
      231 of 397 rows filled instantly, offline, no GitHub rate limit. Uncloned
      rows fill on their next metadata fetch and sort to the bottom meanwhile.
      The date rides along in the exported catalog JSON.

## Clones & workflow

- [ ] Open a clone directly in Cursor / VS Code / Zed from the row menu
- [ ] Per-repo update history (what changed since you last pulled)
- [ ] Strict-license **gate before cloning** (not just an inspector caution)
- [ ] Export a category's clones as a manifest for an AI agent

## GitHub login (next)

- [ ] **GitHub login** (read-only) → stars/owned repos → smarter suggestions
      (plan in [v2.0-roadmap.md](v2.0-roadmap.md), which needs a rewrite first)
- [ ] Apple Intelligence on-device summaries beyond Capture Assist (use cases, note, tags already fill)
- [ ] Batch Capture Assist pass over a shelf or category

Note: the old "Intelligence engine" (graph, recommendations, Compare, Ecosystems,
Runbooks) was removed in 1.9.x. Ideas that depended on it ("bridge SwiftData and
GRDB", "alternative to X" links) are dropped; start from the catalog if wanted.

## Distribution & quality

- [x] ~~Signed, notarized `.dmg` release~~ + ~~Sparkle auto-update~~ (1.5.0) — shipped (`scripts/release.sh`)
- [x] ~~Screenshots in the README~~ — done; a short demo GIF/video still TODO
- [ ] Unit tests: GitHub URL parsing, license matching, dedup keys, sidebar predicates
- [ ] UI smoke tests: capture → categorize → clone → pull
- [ ] Accessibility pass: VoiceOver on list + inspector

## Community

- [ ] Showcase of community skills / integrations that talk to reshelf
      (see "Extending reshelf with skills" in the [README](README.md))

## Explicitly later

- Team sync, cloud accounts, hosted backend
