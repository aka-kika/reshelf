# Security Policy

reshelf is a **local-first** macOS app. It has **no backend and no reshelf
account** — your catalog, backups, and clones all live on your Mac under
`~/reshelf/`, and any third-party credentials (e.g. AI provider keys today, the
planned GitHub token in v2) are stored in the macOS **Keychain**, never in the
repo, `UserDefaults`, SwiftData, or GRDB.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Instead, report privately via **[GitHub Security Advisories](https://github.com/aka-kika/reshelf/security/advisories/new)**
(Security → Report a vulnerability). Include steps to reproduce and the affected
version/commit. We'll acknowledge and work on a fix before any public disclosure.

## Supported versions

reshelf is pre-1.0 and in active testing — only the latest `main` is supported.
