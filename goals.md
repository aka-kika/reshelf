# Goals

Why **reshelf** exists. Aligns with [AGENTS.md](AGENTS.md) and your wider macOS / agent workflow preferences.

## Primary goal

A **personal, local-first shelf** for open-source tools — not a generic bookmark list. You track whether a repo is worth *your* time for *your* lanes (Codex, Ollama/local AI, macOS apps, private work, content/design).

## User outcomes

1. **Capture fast** — GitHub link → metadata in seconds (Quick Capture).
2. **Decide clearly** — status and fit score show what to try next vs ignore.
3. **Filter by intent** — sidebar matches real workflows, not only category names.
4. **Stay private** — no account; catalog on your Mac; optional local AI only.
5. **Grow into analysis** — intelligence DB (GRDB) eventually supports clones, ingestion, and deeper repo context without replacing the simple shelf UI.

## Product principles

- **Mac-native** — unified chrome, split view, keyboard shortcuts (see home AGENTS: Cursor-like sidebar + toolbar discipline).
- **Calm main window first** — stable list/detail and empty states before command palette or menu bar capture.
- **Readable capture UI** — opaque Quick Capture / future palette surfaces, not decorative glass over bright windows.
- **Honest scope** — evaluate and remember tools; not a package manager or full GitHub client.
- **Hideable chrome** — inspector sections and extra metadata should be optional via Settings when we add them.
- **Workflow-aware** — flags and sidebar workflow items mirror how you actually build (Codex, local AI stack, private repos).

## Success signals (informal)

- New repos land via **⌘⇧N**, not lost browser tabs.
- **Useful** and **Testing** lists stay short and actionable.
- Notes are enough to reopen a project months later.
- Ollama assists typing; it does not replace your judgment.
- Intelligence DB stays in sync with the catalog without duplicate manual entry (once bridge exists).

## Non-goals (for now)

- Team libraries or cloud sync
- Required login or third-party analytics
- Installing/cloning repos from the UI (until explicitly designed)
- Replacing Obsidian, Notion, or PKM
- Fourth-column inspectors or disconnected floating side panels

## Doc map

- [README.md](README.md) — run the app
- [features.md](features.md) — shipped behavior
- [future-features.md](future-features.md) — backlog
- [todo.md](todo.md) — next tasks
