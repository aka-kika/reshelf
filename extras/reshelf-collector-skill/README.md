# reshelf-collector skill (for Claude Code)

A [Claude Code](https://claude.com/claude-code) **agent skill** that resurfaces the
*rest* of your reshelf shelf — everything you catalogued **except the Yard Sale** —
led by **The Collector**: the shelved-and-forgotten middle you never promoted to Top
Shelf and often never cloned. It maps the keeper collection with clone status and
**shelf age**, leads with the longest-shelved uncloned picks, and recommends what
deserves promoting, cloning, or (honestly) yard-saling.

Third of the trio: [`reshelf`](../reshelf-skill) reads the *source* of repos already
cloned to `~/reshelf/repos`; [`reshelf-catalog`](../reshelf-catalog-skill) indexes the
*whole* shelf with a top-shelf bias; this one digs through **the rest**, so
kept-around saves don't rot unseen. Read-only — managing the shelf stays in the app.
No MCP required.

## How it works

reshelf stores your whole catalog on disk in plain, scriptable forms:

| What | Where |
|------|-------|
| Live catalog (SwiftData) | `~/reshelf/catalog.store` (SQLite) — primary source |
| Automatic JSON backups | `~/reshelf/backups/catalog-*.json` — fallback |
| Local clones | `~/reshelf/repos/<Category>/<repo>` — for the clone-status join |

Each record carries name, category, GitHub URL, description, stars, license, tags,
fit score, status (`topShelf` / `collector` / `yardSale`), and **added date** — the
resurfacing signal. Yard Sale rows are always excluded: that shelf is on its way out.

## Install

Copy this folder into your personal skills directory:

```bash
cp -R extras/reshelf-collector-skill ~/.claude/skills/reshelf-collector
chmod +x ~/.claude/skills/reshelf-collector/scripts/collection-map.sh
```

(Or symlink it if you want it to track the repo.) Restart your Claude Code session so
the skill is discovered.

## Use

In any Claude Code session, try:

- "what's in my collector — what did I shelve and forget?"
- "what's been sitting uncloned the longest?"
- "anything I collected for local-first sync besides my top picks?"
- "spring-clean my collector: what should I promote, clone, or drop?"

Or invoke it explicitly with `/reshelf-collector`.

The bundled helper gives a fast survey:

```bash
bash scripts/collection-map.sh                     # summary + the forgotten middle
bash scripts/collection-map.sh --status collector  # just The Collector
bash scripts/collection-map.sh --category "AI / Agent"
bash scripts/collection-map.sh --uncloned          # kept, but not on disk
bash scripts/collection-map.sh --oldest            # longest-shelved first
bash scripts/collection-map.sh --search <term>     # match name/desc/tags/category/url
bash scripts/collection-map.sh --tsv               # raw normalized rows to filter yourself
```

Clone status is joined on the **GitHub repo slug** (URL basename). Override the
catalog root with `RESHELF_HOME=/path` (defaults to `~/reshelf`); the clone root
honors a custom Repository Storage location set in the app.

## What's inside

- `SKILL.md` — the skill (workflow + triggering description)
- `scripts/collection-map.sh` — the optional helper (works with plain `sqlite3` too)
