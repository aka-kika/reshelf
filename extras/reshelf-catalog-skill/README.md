# reshelf-catalog skill (for Claude Code)

A [Claude Code](https://claude.com/claude-code) **agent skill** that surveys your
*whole* reshelf shelf — every project you catalogued in the app, **whether or not it
was cloned to disk** — so nothing you shelved gets forgotten. It lists the catalog with
clone status, highlights the **not-cloned gap** (especially your top-shelf picks),
recommends fits across the full shelf, and can pull a not-cloned repo's README from
GitHub on demand.

It's the companion to the [`reshelf`](../reshelf-skill) skill: that one reads the
*source* of repos already cloned to `~/reshelf/repos`; this one reads the app's *full
catalog*. Read-only — managing the shelf stays in the app. No MCP required.

## How it works

reshelf stores your whole catalog on disk in plain, scriptable forms:

| What | Where |
|------|-------|
| Live catalog (SwiftData) | `~/reshelf/catalog.store` (SQLite) — primary source |
| Automatic JSON backups | `~/reshelf/backups/catalog-*.json` — fallback |
| Local clones | `~/reshelf/repos/<Category>/<repo>` — for the clone-status join |

Each record carries name, category, GitHub URL, description, stars, license, tags, fit
score, status (`topShelf` / `collector` / `yardSale`), and added date — enough to
survey and recommend without cloning or hitting the network.

## Install

Copy this folder into your personal skills directory:

```bash
cp -R extras/reshelf-catalog-skill ~/.claude/skills/reshelf-catalog
chmod +x ~/.claude/skills/reshelf-catalog/scripts/catalog-map.sh
```

(Or symlink it if you want it to track the repo.) Restart your Claude Code session so
the skill is discovered.

## Use

In any Claude Code session, try:

- "what's on my top shelf, and did I miss cloning any of them?"
- "recap my whole shelf — not just what's downloaded"
- "what have I saved for note-taking overall, cloned or not?"
- "best thing I shelved for a menu-bar app — is it cloned yet?"

Or invoke it explicitly with `/reshelf-catalog`.

The bundled helper gives a fast survey:

```bash
bash scripts/catalog-map.sh                    # summary: totals, cloned/total, the not-cloned gap
bash scripts/catalog-map.sh --status topShelf  # one status (topShelf | collector | yardSale)
bash scripts/catalog-map.sh --category "AI / Agent"
bash scripts/catalog-map.sh --uncloned --status topShelf   # "did I miss cloning?"
bash scripts/catalog-map.sh --search <term>    # match name/desc/tags/category/url
bash scripts/catalog-map.sh --tsv             # raw normalized rows to filter yourself
```

Clone status is joined on the **GitHub repo slug** (URL basename), because reshelf
clones each repo into a folder named after the repo — and catalog categories
(`AI / Agent`) differ from on-disk folder names (`AI Agent`). Override the catalog root
with `RESHELF_HOME=/path` (defaults to `~/reshelf`); the clone root honors a custom
Repository Storage location set in the app.

## What's inside

- `SKILL.md` — the skill (workflow + triggering description)
- `scripts/catalog-map.sh` — surveys the whole catalog (live store, JSON-backup
  fallback), flags each project cloned vs shelf-only, and highlights the not-cloned gap.
