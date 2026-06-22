---
name: reshelf-catalog
description: >-
  Survey the user's WHOLE reshelf shelf — every project they catalogued in their
  reshelf macOS app, whether or not it was cloned to disk — so nothing they shelved
  gets forgotten. This is the companion to the `reshelf` skill: that one reads the
  source of repos already cloned to ~/reshelf/repos; THIS one reads the app's full
  catalog (live store + JSON backups) so it can also surface picks the user saved but
  never downloaded. Trigger it whenever the user wants the big-picture of their
  collection rather than code from one clone: "what's on my top shelf?", "everything
  I've shelved", "my whole catalog / collection", "did I miss cloning something?",
  "what did I save for X that I haven't downloaded yet?", "what's shelved but not
  cloned", "recap/overview of my shelf", "top-shelf picks I forgot", "what have I
  collected for <topic> overall", or comparing/choosing across saved-but-not-cloned
  options. It lists the catalog with clone status, highlights the not-cloned gap
  (especially top-shelf), recommends fits across the full shelf, and can pull a
  not-cloned repo's README from GitHub on demand. When the user then wants to READ or
  borrow actual source, hand off to the `reshelf` skill (which needs the repo cloned).
  Do NOT use it for: developing the reshelf app itself (its Swift/UI code), reading
  source of an already-cloned repo (use `reshelf`), or discovering brand-new projects
  on the open web.
---

# reshelf-catalog — your whole shelf, including what you never cloned

The user runs **reshelf**, a macOS app that catalogs open-source repos and clones the
keepers to disk. The sibling `reshelf` skill reasons over the **cloned source** in
`~/reshelf/repos/<Category>/<repo>`. But the app's *catalog* is bigger than what's on
disk: it tracks **everything the user shelved**, each tagged with a status —
`topShelf` (their best picks), `collector` (kept around), `yardSale` (on the way out).

This skill reads that catalog so the user never loses track of something they meant to
keep — especially **top-shelf picks they forgot to clone**.

## Where the data lives (no app, no MCP needed)

```
~/reshelf/catalog.store              live SwiftData store (SQLite)  ← primary
~/reshelf/backups/catalog-*.json     timestamped JSON exports        ← fallback
~/reshelf/repos/<Category>/<repo>    the actual clones (for clone-status join)
```

Each catalog record carries: name, category, GitHub URL, short/long description,
stars, license, tags, fit score, status, added date. That's enough to survey,
compare, and recommend **without cloning or hitting the network**.

## How to work through a request

### 1. Map the whole shelf (always start here)

```bash
bash ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh                    # summary + the not-cloned gap
bash ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh --status topShelf  # one status
bash ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh --category "AI / Agent"
bash ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh --uncloned --status topShelf   # "did I miss cloning?"
bash ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh --search <term>    # name/desc/tags/category/url
bash ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh --tsv             # raw rows to filter yourself
```

The summary shows totals, a **cloned / total** breakdown by status and by category,
and the headline list of **top-shelf picks not yet cloned**. Each row is flagged
`[cloned]` (on disk) or `[ shelf]` (catalogued only).

Notes that keep results correct:
- The script prefers the **live store** and silently falls back to the **newest JSON
  backup**; it prints which source it used. If the app is open and you suspect very
  recent edits aren't reflected, mention that the backup may lag.
- Clone status is joined on the **GitHub repo slug** (URL basename), because the app
  clones into a folder named after the repo, not the catalog name. Catalog category
  names (`AI / Agent`) also differ from on-disk folder names (`AI Agent`) — rely on
  the script's flag, don't infer clone status from folders yourself.

### 2. Pin down intent: survey, gap-check, or recommend

- **Survey / recall** ("what's on my shelf for X", "recap my collection") — list the
  relevant slice with clone flags so the user sees the full picture at a glance.
- **Gap-check** ("did I miss something", "what should I have cloned") — lead with
  `--uncloned`, usually scoped to `--status topShelf`. These are the high-intent saves
  that never made it to disk.
- **Recommend** ("best thing I saved for Y") — reason across the **whole** shelf, not
  just clones, using the catalog metadata (relevance, stars, license, recency-by-added,
  fit score). Name a clear pick and a runner-up; say whether each is already cloned.

### 3. Go deeper only when asked

The catalog gives you descriptions, stars, license and tags — often enough. When the
user wants more on a **not-cloned** repo:

- **Read its README from GitHub** without cloning — fetch the repo page or raw README
  (`gh repo view <owner>/<repo>` if `gh` is available, else the raw URL). Summarize
  what it is and whether it fits.
- **Suggest cloning it** if they want to actually study or borrow code — that's the
  reshelf app's job (right-click → Clone Repository). Once cloned, switch to the
  `reshelf` skill to read the real source.

### 4. Recommend, with the clone state made explicit

```
Best fit for <goal>: <repo>   [cloned ✓ | not cloned]
  Why: <relevance, stars, license, fit — from the catalog>
  GitHub: <url>
  Next: <if cloned → "open it with the reshelf skill"; if not → "clone it in the app, then read it">

Runner-up: <repo> — <when you'd pick it instead>   [clone state]
```

Be honest when the shelf is thin for a topic. A weak forced pick is worse than "you
haven't shelved much here; closest is X, and Y is worth saving."

## Relationship to the `reshelf` skill (don't overlap)

- **This skill** = the *index*: the full catalog, clone status, the not-cloned gap,
  cross-shelf recommendations, README-without-cloning.
- **`reshelf` skill** = the *source*: reading, learning from, and borrowing code from
  repos already cloned to `~/reshelf/repos`.

When a survey lands on a cloned repo the user wants to study, hand off to `reshelf`.
When `reshelf` finds a needed repo isn't on disk, this skill can confirm it's shelved
and where it sits.

## Guardrails

- **Read-only.** Don't write to `catalog.store`, the backups, or the clones. Surveying
  and recommending only; the user manages the shelf in the app.
- **Don't run or install** anything from the catalog just to inspect it.
- **Respect licenses** before suggesting code be borrowed (the catalog shows the SPDX
  field; `NOASSERTION` means verify on the repo).
- **Don't touch the reshelf app's own code** — that's a separate development task, not
  this skill.
