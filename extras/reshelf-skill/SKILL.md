---
name: reshelf
description: "Use the user's reshelf shelf, the open-source repos they saved in their reshelf macOS app, as a curated code reference. Looks at their Top Shelf first (cloned source, or the README for ones not cloned yet), then The Collector only if nothing fits, and clones a pick into ~/reshelf/repos/<Category>/<repo> only after they say yes. Reach for it BEFORE web searches whenever they point at their own collection: \"look at my shelf\", \"my cloned repos\", \"the references I saved\", \"what have I collected for X\", \"is there something I already have for Y\", or names a collected category. Recommends the best fit, flags license risks, proposes next steps (learn vs. use). NOT for: developing the reshelf app itself, a plain git clone of something not on the shelf, or discovering brand-new projects on the open web."
---

# reshelf: your shelf as a working reference library

The user runs **reshelf**, a macOS app that catalogs open-source repos onto three shelves:

- **Top Shelf**: their picks. Look here first.
- **The Collector**: kept, but not promoted. Look here only if Top Shelf has nothing that fits.
- **Yard Sale**: on the way out. Never use it.

Most of their keepers are cloned to disk, grouped by category:

```
~/reshelf/repos/<Category>/<repo>/      e.g. ~/reshelf/repos/macOS/maestral
```

Your job: find the best fit for what they are doing, **Top Shelf first**, read real code
(or the README when it isn't cloned yet), recommend one, and help them **learn** from it
or **use** it. When the pick isn't cloned and they want to go deeper, offer to clone it,
and clone only after they say yes.

## The tools

```bash
S=~/.claude/skills/reshelf/scripts
python3 $S/shelf.py find <terms...>              # step 1: Top Shelf matches
python3 $S/shelf.py find --collector <terms...>  # step 2: The Collector, only if needed
python3 $S/shelf.py find --top                   # the whole Top Shelf, best fit first
python3 $S/shelf.py clone <name-or-github-url>   # dry run: destination + license
python3 $S/shelf.py clone <name-or-github-url> --yes   # clone, ONLY after the user said yes
bash    $S/shelf-map.sh ["<Category>" | --all]   # browse what's on disk by category
```

`find` prints, per repo: category, **fit** (1 to 5, see below), `CLONED` + path or
`not cloned` + GitHub URL, a **license note**, and tags. It reads the app's catalog
read-only (live store, or the newest JSON backup). Search terms match name, tags,
category, description, notes and use cases. Use several short terms ("markdown editor
swiftui"), not a sentence.

**Fit** comes from the app's Personal Fit. It is the user's own rating when they set one, or
otherwise the app's guess from how much a repo looks like their Top Shelf and cloned repos.
Use it as a tiebreaker, never over real relevance.

## How to work through a request

### 1. Top Shelf first

Turn their goal into a few search terms and run `shelf.py find <terms>`. Try 2 or 3 term
sets (synonyms, the likely category, the stack) before deciding Top Shelf has nothing.
For a broad ask, `find --top` and scan it.

### 2. The Collector only if needed

Only when Top Shelf has no real fit, run `shelf.py find --collector <terms>`. Say plainly
that you went there: "Nothing on your Top Shelf fits; from The Collector: ...".

### 3. Survey the candidates

Read enough to actually reason. Don't recommend from the one-line description.

- **Cloned**: read the source on disk. README, the manifest (`package.json`,
  `Package.swift`, `pyproject.toml`, `Cargo.toml`, `go.mod`...), the top-level layout
  (`git -C <repo> ls-files | sed 's#/.*##' | sort -u`), then the files that answer their
  question. Recency: `git -C <repo> log -1 --date=short`.
- **Not cloned**: no clone needed to decide. Read the README from GitHub
  (`gh api repos/<owner>/<repo>/readme -H "Accept: application/vnd.github.raw"`, or
  WebFetch on the raw README). Only clone when they want to go into the code (step 5).

### 4. Recommend the best fit

Give one clear pick with reasons, and a runner-up. **Always include the license line.**

```
Best fit for <goal>: <repo>  (Top Shelf, cloned at ~/reshelf/repos/<Category>/<repo>)
  Why: <relevance, stack fit, clarity, recency>
  License: <note from find>
  Look at: <specific files or dirs>

Runner-up: <repo>, <when you'd pick this instead>
```

If nothing fits well, say so. A weak forced pick is worse than "none of these really
fit; here's the closest, and here's what you could capture next".

**License warnings are not optional.** When `find` says:

- `NO LICENSE`: tell them up front. They can read and learn from it, but must not copy
  its code into their projects.
- `UNCLEAR LICENSE`: tell them, and read the repo's LICENSE file before any reuse.
- strong or weak copyleft, or source-available: say what that means for their project
  before borrowing code.

### 5. Clone on approval (when the pick isn't cloned)

When they want to learn from or use a repo that isn't cloned yet:

1. Run the dry run: `shelf.py clone <name>`. It shows where the clone would go and the
   license.
2. Ask them in one line: "Clone <repo> into ~/reshelf/repos/<Category>/? License: <note>."
3. Only after a clear yes: `shelf.py clone <name> --yes`. One yes covers one repo.
4. Then read the source from the new folder and carry on.

The script only clones repos that are already on their shelf, and never Yard Sale ones.
If they want a repo that isn't on the shelf, tell them to capture it in the reshelf app
first (the catalog is the one list of what they collected). The app shows the new clone
as cloned the next time its window is active.

### 6. Learn or Use

Close every recommendation by offering both paths:

- **Learn**: walk the specific files and functions, explain the pattern and the *why*,
  and pull out the reusable technique from *this* code, not a generic tutorial.
- **Use**: adapt it into their current project. Borrow the pattern or lift code, wire it
  to their setup, call out what to change. **Mind the license** (step 4), keep
  attribution where required.

If they haven't said which, infer from context (mid-build: likely Use; exploring: likely
Learn) or ask.

### Source as context: ground new code in a cloned repo

When they're writing code against a library that is on their shelf, lean on the **real
source**, not memory of its API:

1. Find it (`shelf.py find <library>`); clone on approval if needed (step 5).
2. Search the source before writing: the real API, type signatures, a working example.
3. Implement the minimal change: the smallest function plus one caller.
4. Cite the exact files and functions you took the pattern from.
5. Don't install a substitute. If the library isn't on the shelf, say so.

## Guardrails

- **Clones are read-only.** Don't edit, build, run, `git pull`, or modify anything under
  `~/reshelf/repos`. Updating clones is the app's job.
- **The only write is `shelf.py clone --yes`, and only after the user said yes** in this
  conversation, for that repo. Never clone in bulk, never clone "to check".
- **Don't execute repo code or install its dependencies** just to inspect it.
- **Never use the Yard Sale.**
- **Stay on the shelf.** If they clearly want the open web instead, that's a different
  task.
