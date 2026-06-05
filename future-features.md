# Future features

Ideas **not** built yet — a backlog, not a commitment. The headline next item
(in-app **GitHub login**) has its own spec in [v2.0-roadmap.md](v2.0-roadmap.md).

## Capture & data

- [ ] Non-GitHub hosts (GitLab, Codeberg) + manual homepage-only capture
- [ ] Clipboard watcher / drag-URL-to-Dock → Quick Capture without raising the window
- [ ] User-controlled periodic GitHub metadata refresh (rate-limited)
- [ ] "Not checked in 90 days" view using `lastCheckedDate`

## Organization

- [ ] Custom smart collections beyond the built-in sidebar filters
- [ ] Manual category override when the auto-classifier guesses wrong
- [ ] Multiple fit dimensions (docs, maintenance, build quality)
- [ ] "Alternative to X" / related-projects links

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

- [x] ~~Signed, notarized `.dmg` release~~ — shipped (`scripts/release.sh`); Sparkle auto-update still TODO
- [x] ~~Screenshots in the README~~ — done; a short demo GIF/video still TODO
- [ ] Unit tests: GitHub URL parsing, license matching, dedup keys, sidebar predicates
- [ ] UI smoke tests: capture → categorize → clone → pull
- [ ] Accessibility pass: VoiceOver on list + inspector

## Community

- [ ] Showcase of community skills / integrations that talk to reshelf
      (see "Extending reshelf with skills" in the [README](README.md))

## Explicitly later

- Team sync, cloud accounts, hosted backend
