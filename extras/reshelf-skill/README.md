# reshelf skill (for Claude Code)

A [Claude Code](https://claude.com/claude-code) **agent skill** that turns your
reshelf shelf into a working code reference. When you ask your agent about
something you saved, it:

1. looks at your **Top Shelf** first (the source on disk if cloned, the README
   from GitHub if not),
2. looks at **The Collector** only if nothing on Top Shelf fits (never the Yard Sale),
3. recommends the best fit, **with a license warning** when a repo has no license,
   an unclear one, or a copyleft one,
4. offers to **clone** a pick that isn't cloned yet, into
   `~/reshelf/repos/<Category>/<repo>`, and clones **only after you say yes**,
5. helps you **learn** the approach or **use**/borrow the code.

It never changes your clones. The one thing it can write is a new clone of a repo
that is already on your shelf, after you approve it.

## Install or update

In the app: **Settings → General → Agent Skill → Install reshelf Skill…**. Click it
again after every reshelf update that changes the skill; the old copy goes to the
Trash.

Or by hand:

```bash
cp -R extras/reshelf-skill ~/.claude/skills/reshelf
chmod +x ~/.claude/skills/reshelf/scripts/*
```

Restart your Claude Code session so the skill is picked up.

**Upgrading from reshelf 1.11 or earlier?** The old `reshelf-catalog` and
`reshelf-collector` skills are now part of this one. Remove them so your agent
doesn't pick the old ones:

```bash
mv ~/.claude/skills/reshelf-catalog ~/.claude/skills/reshelf-collector ~/.Trash/
```

## Use

In any Claude Code session try:

- "look at my shelf: what have I collected for note-taking, and which should I learn from?"
- "I'm building a menu-bar mac app; what's the best reference I saved and how does it wire up the menu bar?"
- "anything I saved for markdown rendering in SwiftUI? clone the best one if it isn't yet"
- "how do my macOS clones handle global hotkeys?"

Or invoke it explicitly with `/reshelf`.

## What's inside

- `SKILL.md`: the skill (workflow + triggering description)
- `scripts/shelf.py`: finds repos (Top Shelf first, then The Collector) with clone
  status, Personal Fit and a license note, and clones one on approval exactly like the
  app does (dry run unless `--yes`). Reads your catalog read-only.
- `scripts/shelf-map.sh`: maps what's on disk by category, with origin, last-commit
  date, stack guess and README preview; honors a custom Repository Storage location.
