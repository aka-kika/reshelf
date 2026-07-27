# Future features

Ideas **not** built yet — a backlog, not a commitment. The headline next item
(in-app **GitHub login**) has its own spec in [v2.0-roadmap.md](v2.0-roadmap.md).

## Capture & data

- [ ] Non-GitHub hosts (GitLab, Codeberg) + manual homepage-only capture
- [ ] Clipboard watcher / drag-URL-to-Dock → Quick Capture without raising the window
- [ ] User-controlled periodic GitHub metadata refresh (rate-limited)
- [ ] "Not checked in 90 days" view using `lastCheckedDate`

## Organization

- [ ] **Folders for clones, as a sidebar tree** — group cloned repos under folders
      the user creates, e.g. "everything I pulled for project X". Real case: ~100
      repos cloned for a single project, and afterwards there's no way to see which
      ones belonged to it or to let the batch go together. A folder is a user-made
      grouping, *not* a category (categories are a fixed taxonomy) and not a shelf
      status — a repo keeps its category and its shelf while sitting in a folder.
      Sidebar shows folders as an expandable tree under Cloned.
- [ ] **Multi-select + batch actions in the list** — shift/⌘-click a range, then
      move to shelf, add to folder, or remove local clones in one go. Pairs with
      folders above: the point is retiring a whole project's worth of clones at once
      instead of one right-click at a time. Batch unclone must go through the same
      recoverable trash path as the single-repo action, and say how much disk it
      will reclaim before doing it.
- [ ] Custom smart collections beyond the built-in sidebar filters
- [ ] Manual category override when the auto-classifier guesses wrong
- [ ] Multiple fit dimensions (docs, maintenance, build quality)
- [ ] "Alternative to X" / related-projects links
- [x] ~~**"Last updated" as first-class metadata + a sort option**~~ — shipped in
      1.6.0 (2026-07-27): `lastUpdatedDate` on `ToolProject`, a **Recently Updated**
      sort, and a Settings action that backfills from each clone's git log (231 of
      397 rows filled instantly, offline). Uncloned rows fill on next metadata
      fetch. The date travels in the catalog JSON. Original note:
- [ ] ~~"Last updated" as first-class metadata~~ *(kept for context)* — GitHub's
      `pushed_at` is *already* fetched (`QuickCaptureService`) and already stored in
      the intelligence DB (`RepositoryIngestionService` → metadata record). The gap
      is that the list sorts on `ToolProject` (SwiftData) while the date lives in
      GRDB. Needs: a `lastUpdatedDate: Date?` on `ToolProject`, filled on capture and
      on metadata refresh; a fourth sort case beside Recently Added / Name / Stars;
      and a backfill pass for existing rows (model it on Capture Assist's "Fill
      Missing Entries"). For cloned repos there's a second, free, offline source —
      the clone's own last commit date from `git log`. Note the schema hazard: adding
      a field to `ToolProject` migrates the store, so an older build opened
      afterwards can drop the column (same trap as `personalNote`).

## Clones & workflow

- [ ] Open a clone directly in Cursor / VS Code / Zed from the row menu
- [ ] Per-repo update history (what changed since you last pulled)
- [ ] Strict-license **gate before cloning** (not just an inspector caution)
- [ ] Export a category's clones as a manifest for an AI agent

## Intelligence (v2 — behind Labs today)

- [ ] **GitHub login** (read-only) → stars/owned repos → smarter recommendations
      (spec in [v2.0-roadmap.md](v2.0-roadmap.md))
- [ ] Bridge SwiftData catalog ↔ GRDB intelligence as one source of truth
- [ ] **Apple Intelligence** on-device summaries when Foundation Models are wired
- [ ] Batch AI pass over a shelf or category

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
