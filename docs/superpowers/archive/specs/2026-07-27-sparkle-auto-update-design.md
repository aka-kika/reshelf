# Sparkle auto-update — design

**Date:** 2026-07-27 · **Target release:** 1.5.0 · **Status:** approved, not yet implemented

## Problem

reshelf ships as a notarized DMG attached to a GitHub Release. Every update means
downloading and dragging by hand, on every machine. With the catalog now portable across
two Macs (1.4.0), that manual step happens twice per release and will be forgotten.

Sparkle gives the app in-place updates: it polls a signed XML feed, offers the update with
release notes, and installs on approval.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Appcast host | GitHub Pages, dedicated **`gh-pages` branch** | The feed URL is permanent — every shipped copy polls it forever. Pages is stable and CDN-backed. See "Why not `/docs` on main" below. |
| Update archive | ZIP **alongside** the existing DMG | DMG stays the human download (drag-to-Applications). ZIP is what `generate_appcast` expects and avoids mounting a disk image mid-update. |
| Update UX | Auto-check daily, ask before installing | The app must not change under the user mid-session. A menu item covers impatience. |
| Key custody | Keychain + encrypted backup in `_INFRA/backups/` | Matches the existing `reshelf-notary` Keychain pattern. The backup is the safety net — see Risks. |
| App integration | `UpdaterService` wrapper | Matches the existing `Catalog*Service` convention; keeps Sparkle types out of the App and Settings views. |

**Feed URL (permanent):** `https://aka-kika.github.io/reshelf/appcast.xml`

### Why not `/docs` on main

Pages serving `/docs` publishes **everything** in that folder as a website. `docs/` already
holds `superpowers/specs/`, `blog-info.md`, and `reshelf-screenshots-and-seed-repos.md` —
the last of which is explicitly marked `audience: kika-only`. It is untracked today, so
nothing leaks right now, but wiring Pages to `/docs` sets a trap: committing that note
later would silently publish it to a browsable URL.

A `gh-pages` branch holding only `appcast.xml` and release notes has no such failure mode.
The cost is that `scripts/appcast.sh` publishes via a `git worktree` on that branch instead
of committing to `main` — a few extra lines, once.

## Architecture

### `OpenSourceShelf/Services/UpdaterService.swift` (new)

Owns one `SPUStandardUpdaterController(startingUpdater: true, …)`. Exposes:

- `canCheckForUpdates: Bool` — published, drives the menu item's enabled state
- `checkForUpdates()` — user-initiated check
- `automaticallyChecksForUpdates: Bool` — get/set, bound to the Settings toggle
- `lastUpdateCheckDate: Date?` — read-only, shown in Settings

Nothing else in the app imports Sparkle. That boundary is the point: if Sparkle is ever
swapped or removed, one file changes.

### Menu

`CommandGroup(after: .appInfo)` in `OpenSourceShelfApp.swift` adds **"Check for Updates…"**
directly beneath the existing "About reshelf" item, disabled while a check is in flight.

### Settings

The About tab (`SettingsView.swift:585`) gains an *"Automatically check for updates"*
toggle and a last-checked timestamp. Preferences live in Sparkle's own `UserDefaults`
keys via the controller — **not** a parallel `@AppStorage`, which would drift out of sync
with what Sparkle actually does.

### Info.plist

| Key | Value |
|---|---|
| `SUFeedURL` | `https://aka-kika.github.io/reshelf/appcast.xml` |
| `SUPublicEDKey` | (public half of the generated EdDSA key) |
| `SUEnableAutomaticChecks` | `true` |
| `SUScheduledCheckInterval` | `86400` |
| `SUEnableSystemProfiling` | `false` — set explicitly; reshelf is local-first and must not phone home with machine details, and an explicit `false` records that intent rather than leaning on a default that could change. |

## Release pipeline changes (`scripts/release.sh`)

Two parts of the current script stop being correct once Sparkle is embedded.

### 1. Signing becomes inside-out

The script signs the bundle once, justified by an inline comment: *"No embedded frameworks
(statically linked) → a single sign of the bundle is enough."* Sparkle invalidates that.
`Sparkle.framework` contains `Installer.xpc`, `Downloader.xpc`, `Autoupdate.app`, and
`Updater.app`. Each must be signed with Developer ID + hardened runtime, innermost first:

```
XPCServices/*.xpc → Autoupdate.app → Updater.app → Sparkle.framework → reshelf.app
```

Signing only the outer bundle produces an app that notarization rejects. The stale comment
gets updated too — it will otherwise mislead the next person.

### 2. Two notarization passes

Sparkle verifies the downloaded app; a stapled ticket lets that succeed without a network
round-trip. Stapling the `.app` requires notarizing something that contains it, so:

1. Sign app (inside-out, above)
2. `ditto -c -k --keepParent` → `reshelf-<v>.zip`
3. `notarytool submit` the ZIP, `--wait`
4. `stapler staple` the **`.app`**
5. Re-zip the now-stapled app → this is the Sparkle asset
6. `create-dmg` from the stapled app → sign → notarize → staple the DMG (as today)

Two Apple submissions, ~5 minutes each. Unavoidable: the ZIP and the DMG are separate
artifacts and each needs its own ticket.

### 3. Appcast generation (new, `scripts/appcast.sh`)

`generate_appcast` (ships with Sparkle) runs over the directory holding the ZIP, reads the
EdDSA private key from the Keychain, and emits `appcast.xml` with per-release signatures
and lengths. Release notes for the entry come from the matching `CHANGELOG.md` section
rendered to HTML. Both are published to the `gh-pages` branch via a `git worktree`, so the
working tree on `main` is never disturbed mid-release.

Kept as a separate script rather than folded into `release.sh`: appcast regeneration is
occasionally needed on its own (fixing notes, re-signing), and `release.sh` is already long.

`generate_appcast` needs the DMG **and** ZIP URLs to resolve to the GitHub Release assets,
not to Pages — the feed is hosted on Pages, the binaries stay on the Release. The script
passes `--download-url-prefix` accordingly.

## Testing

There is no unit-testable surface here — this is packaging and OS integration. Verification
is empirical and requires **two** Sparkle-enabled builds to exist:

1. Build 1.5.0, install by hand on both Macs.
2. Verify `spctl --assess` still passes and `codesign --verify --deep --strict` accepts every
   nested Sparkle component.
3. Ship a trivial 1.5.1.
4. On the second Mac, confirm the update is offered, the release notes render, and the
   install completes and relaunches.
5. Confirm the catalog survives the update untouched (`~/reshelf/catalog.store`, 397 rows).

Step 5 matters: the store lives outside the app bundle, but an update that disturbed it
would be the single worst possible regression.

## Risks

- **Losing the EdDSA private key is unrecoverable.** Every installed copy trusts exactly one
  public key baked into its `Info.plist`. Without the private half, no future update can
  ever be signed for those installs — users would have to reinstall by hand. Hence the
  backup outside the Keychain.
- **The feed URL is permanent.** Old installs poll whatever shipped in their plist. Moving
  the feed later means stranding them; the Pages URL must be right the first time.
- **1.4.0 cannot self-update.** It has no Sparkle. The 1.5.0 install is manual on both Macs,
  and that is a one-time cost, not a bug.
- **Nested-signing regressions are silent until notarization.** A missed inner component
  surfaces as an Apple rejection minutes into the release, not at build time. Step 2 of
  Testing is the local guard.

## Out of scope

Delta updates, beta/pre-release channels, and automatic (unattended) installs. All are
additive later; none change the decisions above.
