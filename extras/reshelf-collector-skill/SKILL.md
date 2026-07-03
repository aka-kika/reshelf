---
name: reshelf-collector
description: >-
  Resurface the REST of the user's reshelf collection — everything catalogued in
  their reshelf macOS app EXCEPT the Yard Sale — led by The Collector: the
  shelved-and-forgotten middle that was never promoted to Top Shelf and often never
  cloned. Third of the reshelf trio: `reshelf` reads the source of cloned repos,
  `reshelf-catalog` indexes the whole shelf with a top-shelf bias, and THIS one digs
  through the rest so kept-around saves don't rot unseen. Trigger it whenever the
  user asks about the middle of their collection: "what's in my collector?", "the
  rest of my collection", "what did I shelve and forget?", "resurface my shelf",
  "oldest stuff I saved", "what's been sitting uncloned the longest?", "anything I
  collected for X besides my top picks?", "spring-clean my collector", "what should
  I promote or clone from the rest?". It maps the keeper collection (Yard Sale
  always excluded) with clone status and shelf age, leads with the forgotten middle,
  recommends what deserves promoting/cloning, and can pull a not-cloned repo's
  README from GitHub on demand. Hand off to `reshelf` to read cloned source, or to
  `reshelf-catalog` for the whole-shelf index / top-shelf gap. Do NOT use it for:
  developing the reshelf app itself (its Swift/UI code), Yard Sale contents (on the
  way out, by design), or discovering brand-new projects on the open web.
---

# reshelf-collector — the rest of the shelf, before it's forgotten

The user runs **reshelf**, a macOS app that catalogs open-source repos and clones the
keepers to disk. Each catalogued project carries a status: `topShelf` (best picks),
`collector` (kept around — the default), `yardSale` (on the way out). Two sibling
skills already cover the edges: `reshelf` reasons over **cloned source** in
`~/reshelf/repos/<Category>/<repo>`, and `reshelf-catalog` indexes the **whole shelf**
with a top-shelf bias.

This skill owns **the rest**: the keeper collection *minus the Yard Sale*, led by
**The Collector** — things the user deliberately kept but never promoted and often
never cloned. Its job is resurfacing: nothing kept should rot unseen.

## Where the data lives (no app, no MCP needed)

```
~/reshelf/catalog.store              live SwiftData store (SQLite)  ← primary
~/reshelf/backups/catalog-*.json     timestamped JSON exports        ← fallback
~/reshelf/repos/<Category>/<repo>    the actual clones (for clone-status join)
```

Each record carries: name, category, GitHub URL, descriptions, stars, license, tags,
fit score, status, and **added date** — enough to survey, age, and recommend without
cloning or hitting the network.

## How to work through a request

### 1. Map the collection (always start here)

```bash
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh                     # summary + the forgotten middle
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh --status collector  # just The Collector
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh --category "AI / Agent"
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh --uncloned          # kept, but not on disk
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh --oldest            # longest-shelved first
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh --search <term>     # name/desc/tags/category/url
bash ~/.claude/skills/reshelf-collector/scripts/collection-map.sh --tsv               # raw rows to filter yourself
```

**Yard Sale rows never appear** — that shelf is on its way out, by design. Top-shelf
rows do appear (so a topic survey misses nothing) but Collector rows are listed first;
when a top-shelf item comes up, note it's already among the user's best picks.

The summary shows totals, cloned/total by status and category, and the headline list:
**Collector picks not cloned, longest-shelved first** — the forgotten middle.

Notes that keep results correct:
- The script prefers the **live store** and silently falls back to the **newest JSON
  backup**; it prints which source it used.
- Clone status is joined on the **GitHub repo slug** (URL basename) — rely on the
  script's `[cloned]`/`[ shelf]` flag, don't infer from folder names yourself.
- The `added` column is the month the repo was shelved — the resurfacing signal.

### 2. Pin down intent: resurface, survey, or triage

- **Resurface** ("what did I forget?", "oldest stuff I saved") — lead with the
  forgotten middle: uncloned Collector rows, longest-shelved first. Group by category
  and remind the user *why* each was probably saved (description + tags).
- **Survey** ("what's in the rest of my collection for X?") — list the relevant slice,
  Collector first, clone flags and ages visible.
- **Triage** ("spring-clean my collector", "what should I promote or drop?") — for
  each candidate suggest one of: **promote** (it earned Top Shelf), **clone** (worth
  studying — do it in the app), **leave** (fine where it is), or **yard-sale it**
  (say so honestly). The user acts in the app; you only recommend.

### 3. Go deeper only when asked

- **Read a not-cloned repo's README from GitHub** without cloning
  (`gh repo view <owner>/<repo>` if available, else the raw README URL). Summarize
  what it is and whether it still deserves its shelf space.
- **Suggest cloning** when the user wants to actually study or borrow code — that's
  the reshelf app's job (right-click → Clone Repository). Once cloned, switch to the
  `reshelf` skill to read the real source.

### 4. Recommend, with age and clone state explicit

```
From the rest of your shelf, for <goal>: <repo>   [cloned ✓ | not cloned] · shelved <YYYY-MM>
  Why: <relevance, stars, license, fit — from the catalog>
  GitHub: <url>
  Next: <promote / clone in the app / open with the reshelf skill>

Runner-up: <repo> — <when you'd pick it instead>   [clone state · age]
```

Be honest when the middle shelf is thin for a topic. "Your collector has nothing for
this; closest is X on your top shelf" beats a forced pick.

## Relationship to the sibling skills (don't overlap)

- **`reshelf`** = the *source*: reading and borrowing code from cloned repos.
- **`reshelf-catalog`** = the *index*: the whole shelf, the top-shelf not-cloned gap.
- **This skill** = the *rest*: The Collector middle, aged and resurfaced, Yard Sale
  excluded. When a survey lands on a cloned repo the user wants to study, hand off to
  `reshelf`; for whole-shelf questions or top-shelf gaps, hand off to `reshelf-catalog`.

## Guardrails

- **Read-only.** Don't write to `catalog.store`, the backups, or the clones. Shelf
  changes (promote, clone, yard-sale) happen in the app — you recommend, the user acts.
- **Don't run or install** anything from the catalog just to inspect it.
- **Respect licenses** before suggesting code be borrowed (`NOASSERTION` means verify
  on the repo).
- **Don't touch the reshelf app's own code** — that's a development task, not this skill.
