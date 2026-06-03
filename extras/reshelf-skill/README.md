# reshelf skill (for Claude Code)

A [Claude Code](https://claude.com/claude-code) **agent skill** that turns your
reshelf clone library into a working reference: it maps your cloned repos
(grouped by category at `~/reshelf/repos/<Category>/<repo>`), surveys their
source, recommends the best fit for a goal, and proposes next steps — **learn**
the approach or **use**/borrow the code.

It's read-only on your clones (cloning and updating stay in the app).

## Install

Copy this folder into your personal skills directory:

```bash
cp -R extras/reshelf-skill ~/.claude/skills/reshelf
chmod +x ~/.claude/skills/reshelf/scripts/shelf-map.sh
```

(Or symlink it if you want it to track the repo.) Restart your Claude Code
session so the skill is discovered.

## Use

Clone a few repos in the reshelf app first (right-click a repo → **Clone
Repository**), then in any Claude Code session try:

- "look at my shelf — what have I collected for note-taking, and which should I learn from?"
- "I'm building a menu-bar mac app; what's the best reference I saved and how does it wire up the menu bar?"
- "how do my macOS clones handle global hotkeys?"
- "find the best note-taking reference I saved and help me borrow its editor approach into my project"

Or invoke it explicitly with `/reshelf`.

## What's inside

- `SKILL.md` — the skill (workflow + triggering description)
- `scripts/shelf-map.sh` — maps categories/repos with origin, last-commit date,
  stack guess, and README preview; honors a custom Repository Storage location.
