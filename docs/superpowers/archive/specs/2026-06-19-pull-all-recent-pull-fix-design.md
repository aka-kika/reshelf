# Pull All + Recent fix + resilient pull — design

**Date:** 2026-06-19
**Status:** Approved, implementing

Three related catalog-clone improvements. All three share one foundation: a more
resilient "sync to upstream" pull. Build the foundation first, then the two
user-facing features sit on top.

## Background / root causes

These clones (`~/reshelf/repos/<Category>/<repo>`) are **read-only reference
copies** — the user never commits to them.

1. **Pull All missing.** Only "Check Clones for Updates" exists (⌘⇧U → flags each
   behind row with a dot). Actually pulling means opening each repo's inspector and
   clicking "Pull" one at a time.
2. **Palette "Recent" is stale.** `CommandPaletteView` stores recent *search
   strings*, saved only in `handleSubmit()` (Return on free text). Selecting a repo
   result — the normal path — saves nothing, so "Recent" is almost always empty.
3. **Pull fails on diverged clones.** `git pull --ff-only` aborts when a clone has
   diverged. Reproduced on Logseq: `master...origin/master [ahead 23, behind 26]`,
   `fatal: Not possible to fast-forward, aborting`. Cause: Logseq force-pushed/
   rebased `master` after the clone; the 23 "ahead" commits are upstream
   maintainers', not the user's. Working tree was clean.

## Foundation — resilient sync to upstream

`GitClient`: replace the brittle `pullFastForward` strategy with a sync that does
what a read-only mirror wants. New/changed methods:

- `workingTreeIsClean(repositoryURL:) -> Bool` — `git status --porcelain` empty.
- `remoteDefaultBranch(repositoryURL:) -> String?` — resolve the upstream default
  branch name (e.g. `master`) via `git ls-remote --symref origin HEAD` (parse the
  `ref: refs/heads/<name>\tHEAD` line), falling back to `origin/HEAD`.
- `syncToUpstream(repositoryURL:cancellationID:)`:
  1. `git fetch origin` (LFS-bypassed, `--prune --tags`).
  2. Resolve default branch `D`.
  3. If working tree is **not** clean → throw `GitClientError.localChangesPresent`.
  4. `git reset --hard origin/<D>` (LFS-bypassed) — a no-op fast-forward when
     already current, the divergence fix when upstream rewrote history. Lands HEAD
     on the upstream tip. Untracked files untouched (`reset --hard` leaves them).

New error case `GitClientError.localChangesPresent(repository:)` with a clear
message: `"<repo> has local changes — skipped to protect them."`

`CatalogCloneService.pull(_:)` calls `syncToUpstream`. Name kept to minimize churn.
The thrown error surfaces in both the inspector (existing `.error` state) and the
Pull All summary.

LFS bypass (`filter.lfs.*`) is reused exactly as in clone/pull today.

## Item 1 — Pull All (⌘U, flagged-only)

- `OpenSourceShelfApp.swift`: new menu item **"Pull Clones with Updates"** directly
  under "Check Clones for Updates", bound to **⌘U**. ⌘⇧U stays check-only — clean
  pairing (⌘U updates, ⇧⌘U checks). Posts new notification `.pullCloneUpdates`.
  Add `Notification.Name.pullCloneUpdates`.
- `ProjectListView.swift`:
  - Wire `.pullCloneUpdates` through the existing `CatalogMenuActionsModifier`
    (new `onPullCloneUpdates` closure + `.onReceive`).
  - New `pullFlaggedClones()`: pulls only repos currently in `behindProjectIDs`.
    - If empty → `"No clones flagged — run Check Clones for Updates (⌘⇧U) first."`
    - Else, per repo: `CatalogCloneService.pull`, clear its row dot on success,
      tally skipped (local changes) / failed.
    - Progress + summary in the existing `compareNotice` line, e.g.
      `"Pulling 3 clones…"` → `"Updated 2 · 1 skipped (local changes)."`
  - New `@State private var isPullingClones = false` guard (re-entrancy).

## Item 2 — palette "Recent" → "Recently Added"

`CommandPaletteView.swift`:

- Replace `recentSearchesSection` with `recentlyAddedSection`: top 8 repos by
  `ToolProject.addedDate` (desc), rendered as the existing clickable
  `paletteProjectRow`. Shown on the empty-query state, **replacing** today's
  alphabetical first-20 "Projects" list (cleaner, more useful empty state).
- Remove the dead recent-search machinery: `recentSearchesData` `@AppStorage`,
  `recentSearches`, `saveRecentSearch`, and its call in `handleSubmit` (free-text
  Return still applies the search to the main list as before).
- Section header: "Recently Added".

## Files touched

`OpenSourceShelf/Services/Git/GitClient.swift`,
`OpenSourceShelf/Services/CatalogCloneService.swift`,
`OpenSourceShelf/OpenSourceShelfApp.swift`,
`OpenSourceShelf/Views/ProjectListView.swift`,
`OpenSourceShelf/Views/Components/CommandPaletteView.swift`.

## Verification

- No test target exists. Verify by building (`./build.sh`) and exercising the git
  logic directly against the real Logseq clone (diverged, clean tree → expect reset
  to upstream succeeds; simulate a dirty tree → expect skip-with-warning).
- Manual: ⌘⇧U flags Logseq behind; ⌘U pulls it to up-to-date; palette empty state
  shows Recently Added repos.
