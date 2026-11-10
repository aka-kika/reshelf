# Todo

Near-term work for **reshelf**. Check off as you go. Agents: do not recreate this list elsewhere — update here only. Shipped work is listed in [CHANGELOG.md](CHANGELOG.md), not here.

## Open

- [ ] **Fits round 2 leftovers** (branch `project-fits-2-2026-11-10`, build 1.17.0 (41) installed privately 10 Nov; a review runs on the branch next):
  - Settings → General → Sidebar: **Reset to Default** and drag-reorder were checked by tests only (on m1 the Reset button was not reachable by accessibility, drag was not driven). Try both by hand.
  - **New Fits / Analyze All Fits for all repos** (My Repos heading, Shelf menu) is unit-tested only; run it once live with the GitHub token.
  - The fits list **Sort** (Best Fit, `CatalogSortOrder`) has no test group (the enum lives in `ProjectListView.swift`).
  - On macOS 27.2 the system Settings item's accessibility name still ends in "…" (it shows without on 27.3). Watch it after macOS updates.
- [ ] **Release steps for My Repos and Project fits** (branches `project-fits-2026-11-10` and `project-fits-2-2026-11-10`), after the release is installed:
  1. Back up the live skill folder `_INFRA/Skills-collection/kika-skills/reshelf/` to `_INFRA/backups/`.
  2. Copy `extras/reshelf-skill/scripts/shelf.py` and `SKILL.md` into its `claude/` folder (`claude/scripts/shelf.py`, `claude/SKILL.md`).
  3. Add the three `fits` commands and the "fits --here first" line to `cursor/reshelf.mdc` and `general/reshelf.md`. Do **not** replace their `shelf.py`: those copies (20 Oct) are older than `claude/` and lack the clone marker rules (a checkout counts as cloned only with `.git/reshelf-clone`, written after a clone; old clones adopted by origin). Kika decides whether they get the new script.
  4. Run the skill librarian's `librarian_reindex`.
  5. Until a build with My Repos has run, `shelf.py fits` says "No My Repos yet" (the tables do not exist), so the order above matters only for agents' first answer.
- [ ] **⌘⇧U — show clones needing updates first** — after *Check Clones for Updates* runs, sort the repos that have updates available (the orange-dot / "behind" ones) to the **top** of the list, instead of leaving them in place.
- [ ] *[nice-to-have]* **Show changelog on clone update (no AI)** — when pulling updates for a cloned repo, optionally surface the incoming commits using plain git so you can see what changed.
- [ ] **Verify the folder import round-trip on both Macs** — export here, import there, confirm folders match by name rather than duplicating. The export half is proven (the app's own backup writes folders + memberships correctly); the import half has only been reasoned through, not exercised.
- [ ] **The app's docs site** — the how-to/screenshot docs decided to live on the site rather than in-app (no bundled PDF). The repo has no `homepageUrl` set yet either.
- [ ] **GitHub login inside the app** (first v2 item) — in-app "Connect GitHub" flow: OAuth device flow (primary) + fine-grained PAT (fallback), token in **Keychain**, read-only. The plan in [v2.0-roadmap.md](v2.0-roadmap.md) predates the 1.9.x removals and needs a rewrite before any work.
- [ ] UI smoke tests (see [future-features.md](future-features.md)). Logic tests exist since 1.16.0: `bash Tests/run.sh` (swiftc, in-memory stores and temp folders, no Xcode test target so nothing opens the real catalog).

## Dead Intelligence code

The Labs mode and the v2 engine (Queue, Compare, Ecosystems, Workflows, My Stack, Runbooks, graph, embeddings, Explore) were removed in 1.9.x (about 78 files).

- **Removed in 1.15.0:** the dead parts of the old GRDB API, the Ollama and cloud-provider AI code (Capture Assist on-device Apple Intelligence is the only AI left), and the unused refresh-bus events. **In 1.15.2:** the dead `AppSettings` fields, and one shared GitHub link reader instead of four.
- **Still there on purpose:** `IntelligenceDatabase` and its migrations (up to `v13_runbook_freshness_metadata`), set up at launch; `CatalogCaptureIntelligenceService`, which records GitHub topics and description when a repo is captured or imported; and the inspector reads that metadata. The `fitScore` fields stay because export/backup files carry them and older reshelf versions require them when importing.
- [ ] Later, if wanted: move the few GitHub fields still read from GRDB into SwiftData and drop the SQLite file. Needs a migration plan so no one loses data; not urgent.

## Done recently

Full history is in [CHANGELOG.md](CHANGELOG.md).
