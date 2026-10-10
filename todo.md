# Todo

Near-term work for **reshelf**. Check off as you go. Agents: do not recreate this list elsewhere — update here only. Shipped work is listed in [CHANGELOG.md](CHANGELOG.md), not here.

## Open

- [ ] **Bug (Kika, 2026-10-03): Delete in the inspector removes the repo with no confirmation.** It takes the whole entry out of the catalog at once (no "are you sure" sheet) and leaves the local clone on disk, so the folder is orphaned. Seen with omnivore and Loop: Kika meant to remove only the clones; both entries vanished, both clones stayed in `~/reshelf/repos`. Fix: a confirmation before deleting (name the repo; say whether its clone is removed too), and offer "Remove Local Clone" as the usual choice. The app's own `~/reshelf/backups/catalog-2026-10-03-00*.json` holds the two entries.
- [ ] **⌘⇧U — show clones needing updates first** — after *Check Clones for Updates* runs, sort the repos that have updates available (the orange-dot / "behind" ones) to the **top** of the list, instead of leaving them in place.
- [ ] *[nice-to-have]* **Show changelog on clone update (no AI)** — when pulling updates for a cloned repo, optionally surface the incoming commits using plain git so you can see what changed.
- [ ] **Verify the folder import round-trip on both Macs** — export here, import there, confirm folders match by name rather than duplicating. The export half is proven (the app's own backup writes folders + memberships correctly); the import half has only been reasoned through, not exercised.
- [ ] **The app's docs site** — the how-to/screenshot docs decided to live on the site rather than in-app (no bundled PDF). The repo has no `homepageUrl` set yet either.
- [ ] **GitHub login inside the app** (first v2 item) — in-app "Connect GitHub" flow: OAuth device flow (primary) + fine-grained PAT (fallback), token in **Keychain**, read-only. The plan in [v2.0-roadmap.md](v2.0-roadmap.md) predates the 1.9.x removals and needs a rewrite before any work.
- [ ] Unit tests and UI smoke tests (see [future-features.md](future-features.md)).

## Dead Intelligence code

The Labs mode and the v2 engine (Queue, Compare, Ecosystems, Workflows, My Stack, Runbooks, graph, embeddings, Explore) were removed in 1.9.x (about 78 files).

- **Removed in 1.15.0:** the dead parts of the old GRDB API, the Ollama and cloud-provider AI code (Capture Assist on-device Apple Intelligence is the only AI left), and the unused refresh-bus events. **In 1.15.2:** the dead `AppSettings` fields, and one shared GitHub link reader instead of four.
- **Still there on purpose:** `IntelligenceDatabase` and its migrations (up to `v13_runbook_freshness_metadata`), set up at launch; `CatalogCaptureIntelligenceService`, which records GitHub topics and description when a repo is captured or imported; and the inspector reads that metadata. The `fitScore` fields stay because export/backup files carry them and older reshelf versions require them when importing.
- [ ] Later, if wanted: move the few GitHub fields still read from GRDB into SwiftData and drop the SQLite file. Needs a migration plan so no one loses data; not urgent.

## Done recently

Full history is in [CHANGELOG.md](CHANGELOG.md).
