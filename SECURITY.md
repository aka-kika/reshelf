# Security Policy

reshelf is a **local-first** macOS app. It has **no backend and no reshelf
account**: your catalog, backups and clones all live on your Mac under
`~/reshelf/`.

## What reshelf stores and sends

- **GitHub token (optional).** If you add one in Settings → Capture, it is
  stored in the macOS **Keychain** (item `reshelf.github-token`), never in the
  repo, `UserDefaults`, SwiftData or the SQLite database. It is sent only to
  `api.github.com`, to read repo info with a higher rate limit. It is not passed
  to `git`, so reshelf clones public repos only.
- **No AI keys.** The only AI is on-device Apple Intelligence; there are no
  cloud AI providers and no keys to store.
- **Network.** reshelf talks to GitHub (the API, `git clone` / `fetch` /
  `ls-remote`, owner avatars as icons) and fetches its Sparkle update feed. The
  README's "Privacy and network" section lists each case.
- **Commands.** The only program reshelf runs is `git` (clone, pull,
  `ls-remote`). It never runs anything inside a cloned repo.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Instead, report privately via **[GitHub Security Advisories](https://github.com/aka-kika/reshelf/security/advisories/new)**
(Security → Report a vulnerability). Include steps to reproduce and the affected
version/commit. We'll acknowledge and work on a fix before any public disclosure.

## Supported versions

Only the latest release (and `main`) gets security fixes.
