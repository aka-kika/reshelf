---
name: reshelf
description: >-
  Use the user's reshelf shelf — the open-source repos they cloned to disk with
  their reshelf macOS app, full source organized by category at
  ~/reshelf/repos/<Category>/<repo> — as a hands-on code reference they already
  curated. Reach for it before searching the open web whenever the user points at
  repos they already have. Trigger this STRONGLY, even when the user never says the
  word "reshelf", whenever they gesture at their own collection: "look at my shelf",
  "my cloned repos", "the repos/references I saved", "what have I collected for X",
  "my catalog", "stuff I cloned", "is there something I already have for Y", or they
  name a category they've collected and want to learn from it, borrow patterns from
  it, compare options, or pick the best one. Typical asks: "what have I got for
  note-taking and which should I learn from?", "best reference I saved for a menu-bar
  app — how does it wire it up?", "how do my macOS clones do global hotkeys?", "I'm
  building Y, what on my shelf is a good base and what should I copy?". It maps the
  categories and repos, reads their source/READMEs/manifests, recommends the best
  fit for the goal, and proposes next steps (learn vs. use, with license awareness).
  Do NOT use it for: developing the reshelf app itself (editing its Swift/UI code), a
  plain "git clone <url>" or running/updating one specific repo, discovering
  brand-new projects on the open web, or working on unrelated repo folders like
  ~/Projects or the repo you're currently in.
---

# reshelf — your cloned repos as a working reference library

The user runs **reshelf**, a macOS app that catalogs open-source repos and clones
the keepers to disk, **grouped by category**:

```
~/reshelf/repos/<Category>/<repo>/      e.g. ~/reshelf/repos/macOS/maestral
```

These are **full clones** — all the real source is there. Your job is to turn that
shelf into something useful in the moment: help the user **learn** from real code,
**borrow** proven patterns, **compare** options, and decide **what to use next**.

This beats a cold web search because the user already curated these — they're
pre-filtered to things this person cares about and trusts.

## How to work through a request

### 1. Map the shelf (always start here)

Run the bundled script to see what's on disk — it's fast and avoids guesswork:

```bash
bash ~/.claude/skills/reshelf/scripts/shelf-map.sh              # categories + counts
bash ~/.claude/skills/reshelf/scripts/shelf-map.sh "<Category>" # repos in one category
bash ~/.claude/skills/reshelf/scripts/shelf-map.sh --all        # everything
```

For each repo it prints the git origin, last-commit date, a stack guess, tracked
file count, and the first lines of the README. That's usually enough to orient
before you open anything.

The script resolves the clone root from the app's setting, so it works even if the
user moved their Repository Storage folder.

### 2. Pin down the goal and the category

Map the user's intent to a category folder. Category names are human-readable and
may contain spaces (`"AI Agent"`, `"Internal Tools"`) — **quote paths**.

- If they named a category, use it.
- If they described a *topic* ("note apps", "menu-bar utilities", "RAG"), don't
  assume it equals a folder name. List categories, then scan repo names + READMEs
  to find the matching repos — a good note-taking reference might live under
  `Knowledge`, `macOS`, or `Workspace` depending on how it was classified.
- If nothing fits, say so plainly and suggest what they could clone next (see §6).

### 3. Survey the candidates

For the repos in scope, read enough to actually reason — don't recommend from the
README alone:

- **README / docs** — what it is, scope, intended use.
- **Manifest** — `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`,
  `Package.swift`, etc. — language, dependencies, real surface area.
- **Structure** — `git -C <repo> ls-files | sed 's#/.*##' | sort -u` for a quick
  top-level layout; then open the files that matter to the user's goal.
- **Signals of fit & health** — relevance to the goal first, then recency
  (`git -C <repo> log -1 --date=short`), clarity, size, dependency weight, and
  **license** (`LICENSE`) if they might borrow code.

Read the *specific* source that answers the question. If they ask "how do these do
global hotkeys," go find the hotkey code, don't summarize the project.

### 4. Recommend the best fit

When the user wants "the best one," give a clear pick with reasons — and name the
runner-up so they can judge the tradeoff. Use this shape:

```
Best fit for <goal>: <repo>  (~/reshelf/repos/<Category>/<repo>)
  Why: <relevance to the goal, stack fit, clarity, recency, license>
  Look at: <specific files/dirs that show the relevant implementation>

Runner-up: <repo> — <when you'd pick this instead>
(Also on the shelf: <others>, less suited because <one-line reason>.)
```

Be honest when the shelf is thin or nothing's a great match — a weak forced pick is
worse than saying "none of these really fit; here's the closest, and here's what to
clone."

### 5. Offer the next step: Learn or Use

Close every recommendation by offering both paths, then go as deep as they want:

- **Learn** — teach how the chosen repo does the thing. Walk specific files and
  functions, explain the pattern and the *why*, and pull out the reusable technique
  (not a generic tutorial — the actual approach in *this* code).
- **Use** — adapt it into the user's current project. Borrow the pattern or lift
  code, wire it to their setup, and call out anything to change. **Mind the
  license**: check `LICENSE`, keep attribution where required, and flag copyleft
  (GPL/AGPL) before copying code into their project.

If they haven't said which, ask — or infer from context (mid-build → likely Use;
exploring → likely Learn).

### Source as context: ground new code in a cloned repo

The strongest form of **Use** — when the user is writing code against a library or
framework that reshelf has already cloned, lean on the **real source**, not your
memory of its API. Local source beats stale docs: it stops you inventing functions
that don't exist and keeps you to the library's actual conventions.

When they're building against a cloned dependency:

1. **Find the clone** for that library (`shelf-map.sh "<Category>"`, or by name).
2. **Search the source before writing** — grep for the real API, type signatures, and
   a working example; read the files that matter, not just the README.
3. **Implement the minimal change** — the smallest service function plus one caller;
   keep the diff small.
4. **Cite your sources** — name the exact files/functions you took the pattern from,
   so the user can verify against the real code.
5. **Don't install a substitute** — if the real source is on the shelf, use it. If a
   needed library *isn't* cloned, say so (and suggest cloning it) rather than guessing
   the API or pulling in a different package.

A prompt you can hand to another agent (or follow yourself):

```
Build <feature>. We use <library>, cloned at ~/reshelf/repos/<Category>/<library>.
Before coding: search that clone for the correct API and patterns, then implement
only the minimal function + one caller. Keep the diff small, and tell me which
source files/functions you referenced.
```

### When the shelf can't answer

If the category is empty, missing, or has no good fit, say so and suggest **what to
add** — specific repos or search terms worth cloning into reshelf — so the library
gets better. The user clones from the app (right-click → Clone Repository); you map
and reason over what's there.

## Guardrails

- **Treat clones as read-only reference.** Don't edit, build, run, `git pull`, or
  modify anything under `~/reshelf/repos`. Read and learn; apply changes in the
  user's *own* project. (Updating clones is the app's job, not this skill's.)
- **Don't execute repo code or install their dependencies** just to inspect —
  reading the source is enough and safer.
- **Respect licenses** before copying code anywhere.
- **Stay on the shelf.** This skill is about *their* cloned repos. If they clearly
  want the open web instead, that's a different task.
