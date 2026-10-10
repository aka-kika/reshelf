# Contributing to reshelf

Thanks for your interest in **reshelf** — a local-first macOS app for keeping a
personal shelf of open-source repos. Contributions of all sizes are welcome:
bug reports, fixes, features, docs, and design feedback.

> **Status:** reshelf is a shipping app (signed and notarized, updates through
> Sparkle). It is a catalog: capture, shelves, categories, clones. The old
> "Intelligence" engine (Labs mode) was removed in 1.9.x. Expect small rough edges.

## Ground rules

- **Be kind.** Assume good intent; keep discussion constructive.
- **One concern per PR.** Small, focused changes are reviewed and merged faster.
- **No secrets in the repo.** Keys and tokens (for example the future GitHub
  login) belong in the macOS **Keychain** at runtime — never commit them, and
  never add them to `UserDefaults`, SwiftData, or the SQLite file.

## Getting set up

**Requirements:** macOS with **Xcode 16+** (Swift 6, SwiftUI, SwiftData).
Dependencies (GRDB = a SQLite toolkit, Sparkle = auto-update) resolve via Swift Package Manager on first build.

```bash
# From the repo root (where OpenSourceShelf.xcodeproj lives):
bash build.sh          # Debug build → .build/reshelf.app
# or open in Xcode:
#   scheme "OpenSource Shelf"  (the target/module keep the legacy name;
#   the built app is reshelf.app via PRODUCT_NAME), then ⌘R.
```

**Where the app keeps data** (so you know what you're touching while testing):

| What | Where |
|------|-------|
| Catalog (projects, settings) | `~/reshelf/catalog.store` (SwiftData, isolated) |
| Automatic JSON backups | `~/reshelf/backups/` (last 30) |
| Local clones | `~/reshelf/repos/<Category>/<repo>` (default; changeable in Settings) |
| GitHub metadata (small SQLite file, GRDB) | `~/reshelf/database/opensource-shelf.sqlite` |

## ⚠️ Adding or removing Swift files

This Xcode project uses **explicit file lists in `project.pbxproj`** — it is
**not** a synchronized/folder-based group. If you add a new `.swift` file, it
will **not** compile until you register it. Each new file needs **four** entries
in `OpenSourceShelf.xcodeproj/project.pbxproj`, each with a unique 24-hex ID:

1. A `PBXFileReference`
2. A `PBXBuildFile`
3. A child entry in its group
4. An entry in the target's `Sources` build phase

The easiest path is to **add the file in Xcode** (which does this for you), then
commit the resulting `project.pbxproj` diff. If you edit the pbxproj by hand,
build before committing to confirm it links.

## Branches and PRs

1. Branch off `main` (e.g. `fix/clone-lfs`, `feat/github-login`).
2. Keep the change focused; update docs (`README.md`, `features.md`,
   `todo.md`) when behavior changes.
3. **Build green** before opening the PR (`bash build.sh` → `BUILD SUCCEEDED`).
4. Open a PR against `main` with a clear description of *what* and *why*, plus
   manual test steps and screenshots for UI changes.

## Code style

- Swift 6, SwiftUI-first. Follow the patterns already in the file you're editing.
- Prefer small, well-named views/services over large ones.
- Comments explain **why**, not what — especially for non-obvious macOS / layout
  quirks (the codebase has several measured-constant comments; keep them).
- Keep it local-first and AI-light: the only AI is on-device Apple Intelligence
  (Capture Assist). Please do not add cloud AI providers or other cloud-only
  dependencies without opening an issue first.
- The app never runs shell commands from the UI except plain `git` for clone,
  pull and update checks.

## Reporting bugs / requesting features

Use the **issue templates** (Bug report / Feature request). For bugs, include
your macOS + Xcode versions and exact steps. For data-loss or backup issues,
mention whether a snapshot exists in `~/reshelf/backups/`.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
