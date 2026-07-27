# Sparkle Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give reshelf in-app updates via Sparkle, so a new release installs itself instead of being downloaded and dragged by hand on every machine.

**Architecture:** Sparkle 2.9.4 arrives via SPM. A single `UpdaterService` wraps `SPUStandardUpdaterController` so no other file imports Sparkle; a menu item and a Settings toggle drive it. The release pipeline gains inside-out signing of Sparkle's nested components, a second notarization pass so the ZIP's `.app` carries a stapled ticket, and a separate script that publishes the signed appcast to a `gh-pages` branch.

**Tech Stack:** Swift 5 / SwiftUI, SwiftData, Xcode project (manual `.pbxproj` edits — this project has no `Package.swift` and no file-system-synchronized groups), Sparkle 2.9.4, `codesign`, `notarytool`, `stapler`, `create-dmg`, `generate_appcast`, `gh`.

## Global Constraints

- **Feed URL is permanent and exact:** `https://aka-kika.github.io/reshelf/appcast.xml` — every shipped copy polls it forever. Never change it after 1.5.0 ships.
- **Sparkle version:** 2.9.4, `upToNextMajorVersion` — matches the GRDB dependency style already in the project.
- **Deployment target:** macOS 14.0 (`LSMinimumSystemVersion`). Do not raise it.
- **Signing identity:** pin by hash `ADC1CB6085203C50EB344490FD8FC03345838EFB` — the Keychain holds two identical "Developer ID Application: Veronica Loren (P5RB3W3D58)" certs, so name-based lookup fails as ambiguous.
- **Notary profile:** `reshelf-notary` (Keychain), overridable via `RESHELF_NOTARY_PROFILE`.
- **Scheme name is `OpenSource Shelf`; built product is `reshelf.app`.** They differ — do not "fix" this.
- **Only `UpdaterService.swift` may `import Sparkle`.** Any other file importing it is a review rejection.
- **`SUEnableSystemProfiling` must be `false`.** reshelf is local-first; it must not report machine details.
- **There is no XCTest target in this project.** Do not invent one or add test files. Every task's verification is a real command whose output is checked — build, `codesign --verify`, `plutil`, or driving the running app. This is stated per-step; follow it literally rather than substituting unit tests.
- **New Swift files must be registered in `OpenSourceShelf.xcodeproj/project.pbxproj` by hand** (PBXFileReference + group children + PBXBuildFile + Sources phase). Adding a file to disk alone will not compile it.

---

### Task 1: Generate the EdDSA key pair and back it up

The private key signs every future update. If it is lost, existing installs can never be updated again — there is no recovery path. Do this first and confirm the backup before writing any code.

**Files:**
- Create: `~/_KIKA_MAIN/_INFRA/backups/reshelf-sparkle-eddsa-key.txt` (local-only, never synced)
- No repo files change in this task.

**Interfaces:**
- Consumes: nothing.
- Produces: the **public key string** (base64, ~44 chars) that Task 4 writes into `Info.plist` as `SUPublicEDKey`.

- [ ] **Step 1: Fetch Sparkle's distribution tools**

Sparkle's `generate_keys` and `generate_appcast` binaries ship in the release tarball, not in the SPM checkout's usable path. Download once:

```bash
mkdir -p ~/_KIKA_MAIN/_INFRA/tools
cd ~/_KIKA_MAIN/_INFRA/tools
curl -fsSL -o sparkle-2.9.4.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz
mkdir -p sparkle-2.9.4 && tar -xf sparkle-2.9.4.tar.xz -C sparkle-2.9.4
ls sparkle-2.9.4/bin/
```

Expected: `bin/` lists `generate_appcast`, `generate_keys`, `sign_update`.

- [ ] **Step 2: Generate the key pair into the Keychain**

```bash
~/_KIKA_MAIN/_INFRA/tools/sparkle-2.9.4/bin/generate_keys
```

Expected: prints a public key and states the private key was stored in the Keychain. **Copy the public key string** — it is needed in Task 4. If it reports an existing key, run with `-p` to print the public key instead of generating a second one.

- [ ] **Step 3: Export the private key to the local backup**

```bash
mkdir -p ~/_KIKA_MAIN/_INFRA/backups
~/_KIKA_MAIN/_INFRA/tools/sparkle-2.9.4/bin/generate_keys -x \
  ~/_KIKA_MAIN/_INFRA/backups/reshelf-sparkle-eddsa-key.txt
chmod 600 ~/_KIKA_MAIN/_INFRA/backups/reshelf-sparkle-eddsa-key.txt
```

- [ ] **Step 4: Verify the backup is real and readable**

```bash
wc -c ~/_KIKA_MAIN/_INFRA/backups/reshelf-sparkle-eddsa-key.txt
ls -l ~/_KIKA_MAIN/_INFRA/backups/reshelf-sparkle-eddsa-key.txt
```

Expected: non-zero byte count and mode `-rw-------`. **Do not print the file's contents** — it is private key material.

- [ ] **Step 5: Confirm the backup file is outside any git repo**

```bash
git -C ~/_KIKA_MAIN/_INFRA/backups rev-parse --is-inside-work-tree 2>&1 | head -1
```

Expected: an error like `not a git repository`. If it *is* a repo, move the key elsewhere before continuing — a committed private key is a permanent leak.

No commit in this task; nothing in the repo changed.

---

### Task 2: Add the Sparkle SPM dependency

**Files:**
- Modify: `OpenSourceShelf.xcodeproj/project.pbxproj` (package reference, product dependency, frameworks phase)

**Interfaces:**
- Consumes: nothing.
- Produces: the `Sparkle` module, importable in Task 3.

- [ ] **Step 1: Add the three pbxproj entries**

Mirror the existing GRDB declarations at `project.pbxproj:1936-1957`. Add to the `packageReferences` list:

```
				5PARKLE0001234567890ABCD /* XCRemoteSwiftPackageReference "Sparkle" */,
```

Add these two objects next to the GRDB ones, before the closing `};` of the objects section:

```
		5PARKLE0002234567890ABCD /* Sparkle */ = {
			isa = XCSwiftPackageProductDependency;
			package = 5PARKLE0001234567890ABCD /* XCRemoteSwiftPackageReference "Sparkle" */;
			productName = Sparkle;
		};
		5PARKLE0001234567890ABCD /* XCRemoteSwiftPackageReference "Sparkle" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/sparkle-project/Sparkle.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 2.9.4;
			};
		};
```

- [ ] **Step 2: Add it to the target's package product dependencies and Frameworks phase**

Find the target's `packageProductDependencies` list (the one containing `F429640EF7600E3151FF9C01 /* GRDB */`) and add:

```
				5PARKLE0002234567890ABCD /* Sparkle */,
```

Then add a build file object and reference it from the Frameworks build phase, mirroring `64353B5CB9B8DE5AA33C7EB9 /* GRDB in Frameworks */`:

```
		5PARKLE0003234567890ABCD /* Sparkle in Frameworks */ = {
			isa = PBXBuildFile;
			productRef = 5PARKLE0002234567890ABCD /* Sparkle */;
		};
```

- [ ] **Step 3: Verify the project file is still valid**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
plutil -lint OpenSourceShelf.xcodeproj/project.pbxproj
```

Expected: `OK`. If it errors, the edit broke the format — revert with `git checkout OpenSourceShelf.xcodeproj/project.pbxproj` and redo.

- [ ] **Step 4: Resolve the package and build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" \
  -configuration Debug -derivedDataPath .build/DerivedData build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, and the log shows Sparkle being resolved/fetched. Ignore any SourceKit "Cannot find type" diagnostics — only the build result matters.

- [ ] **Step 5: Commit**

```bash
git add OpenSourceShelf.xcodeproj/project.pbxproj
git commit -m "Add Sparkle 2.9.4 via SPM"
```

---

### Task 3: Add UpdaterService

**Files:**
- Create: `OpenSourceShelf/Services/UpdaterService.swift`
- Modify: `OpenSourceShelf.xcodeproj/project.pbxproj` (register the new file)

**Interfaces:**
- Consumes: the `Sparkle` module from Task 2.
- Produces: `final class UpdaterService: ObservableObject` with:
  - `static let shared: UpdaterService`
  - `@Published private(set) var canCheckForUpdates: Bool`
  - `func checkForUpdates()`
  - `var automaticallyChecksForUpdates: Bool { get set }`
  - `var lastUpdateCheckDate: Date? { get }`

  Task 4 uses `checkForUpdates()` and `canCheckForUpdates`; Task 5 uses `automaticallyChecksForUpdates` and `lastUpdateCheckDate`. Use these exact names.

- [ ] **Step 1: Write the file**

```swift
import Foundation
import Combine
import Sparkle

/// The app's only contact point with Sparkle. Everything else talks to this type,
/// so swapping or removing the update framework touches exactly one file.
///
/// Sparkle owns the update preferences in its own `UserDefaults` keys — this
/// deliberately does *not* mirror them into `@AppStorage`, which would drift out
/// of sync with what the updater actually does.
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    /// Drives the menu item's enabled state — Sparkle refuses overlapping checks.
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}
```

- [ ] **Step 2: Register the file in the Xcode project**

Add a `PBXFileReference`, a group-children entry, a `PBXBuildFile`, and a Sources-phase entry, mirroring the existing `CatalogImportService.swift` entries. Use id `5PARKLE0004234567890ABCD` for the file reference and `5PARKLE0005234567890ABCD` for the build file:

```
		5PARKLE0004234567890ABCD /* UpdaterService.swift */ = {
			isa = PBXFileReference;
			lastKnownFileType = sourcecode.swift;
			name = "UpdaterService.swift";
			path = "OpenSourceShelf/Services/UpdaterService.swift";
			sourceTree = SOURCE_ROOT;
		};
```

- [ ] **Step 3: Verify project validity and build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
plutil -lint OpenSourceShelf.xcodeproj/project.pbxproj
xcodebuild -project OpenSourceShelf.xcodeproj -scheme "OpenSource Shelf" \
  -configuration Debug -derivedDataPath .build/DerivedData build 2>&1 | tail -5
```

Expected: `OK`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Confirm the Sparkle import is contained**

```bash
grep -rln "import Sparkle" --include="*.swift" OpenSourceShelf/
```

Expected: exactly one line — `OpenSourceShelf/Services/UpdaterService.swift`. Any other file is a constraint violation.

- [ ] **Step 5: Commit**

```bash
git add OpenSourceShelf/Services/UpdaterService.swift OpenSourceShelf.xcodeproj/project.pbxproj
git commit -m "Add UpdaterService wrapping Sparkle"
```

---

### Task 4: Wire the menu item and Info.plist keys

After this task the app compiles with a working "Check for Updates…" item. It will report a feed error until Task 7 publishes the appcast — that is expected, not a failure.

**Files:**
- Modify: `OpenSourceShelf/OpenSourceShelfApp.swift:161-165` (the `.appInfo` command group)
- Modify: `OpenSourceShelf/Info.plist`

**Interfaces:**
- Consumes: `UpdaterService.shared.checkForUpdates()` and `.canCheckForUpdates` from Task 3.
- Produces: nothing later tasks depend on in code.

- [ ] **Step 1: Add the menu item**

Replace the existing `CommandGroup(replacing: .appInfo)` block with:

```swift
            CommandGroup(replacing: .appInfo) {
                Button("About reshelf") {
                    Self.showAboutPanel()
                }
                Button("Check for Updates…") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.canCheckForUpdates)
            }
```

And add this property alongside the other `@StateObject`s at the top of `OpenSourceShelfApp` (near `@StateObject private var appRefreshStore`):

```swift
    @StateObject private var updaterService = UpdaterService.shared
```

- [ ] **Step 2: Add the five Info.plist keys**

Substitute the real public key from Task 1 Step 2 for `PASTE_PUBLIC_KEY_FROM_TASK_1`:

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
P=OpenSourceShelf/Info.plist
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://aka-kika.github.io/reshelf/appcast.xml' $P
/usr/libexec/PlistBuddy -c 'Add :SUPublicEDKey string PASTE_PUBLIC_KEY_FROM_TASK_1' $P
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' $P
/usr/libexec/PlistBuddy -c 'Add :SUScheduledCheckInterval integer 86400' $P
/usr/libexec/PlistBuddy -c 'Add :SUEnableSystemProfiling bool false' $P
```

- [ ] **Step 3: Verify the keys landed correctly**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
for k in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUScheduledCheckInterval SUEnableSystemProfiling; do
  printf "%-28s " "$k"
  /usr/libexec/PlistBuddy -c "Print :$k" OpenSourceShelf/Info.plist
done
```

Expected: the exact feed URL, a ~44-character key, `true`, `86400`, and `false`. A `SUPublicEDKey` still reading `PASTE_PUBLIC_KEY_FROM_TASK_1` means Step 2 was run unedited — fix before continuing, or every update signature check will fail.

- [ ] **Step 4: Build and confirm the menu item appears**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -E "error:|BUILD|✅"
open .build/reshelf.app && sleep 6
osascript -e 'tell application "System Events" to tell process "reshelf" to get name of menu items of menu 1 of menu bar item "reshelf" of menu bar 1'
```

Expected: `** BUILD SUCCEEDED **`, then the menu list includes `Check for Updates…` directly after `About reshelf`.

- [ ] **Step 5: Quit the app and commit**

```bash
osascript -e 'tell application "reshelf" to quit'
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git add OpenSourceShelf/OpenSourceShelfApp.swift OpenSourceShelf/Info.plist
git commit -m "Wire Check for Updates menu item and Sparkle Info.plist keys"
```

---

### Task 5: Add the Settings toggle

**Files:**
- Modify: `OpenSourceShelf/Views/SettingsView.swift` (About tab, after the `Text("Version \(appVersionString)")` line at `:610`)

**Interfaces:**
- Consumes: `UpdaterService.shared.automaticallyChecksForUpdates` and `.lastUpdateCheckDate` from Task 3.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add local state near the other `@State` properties in `SettingsView`**

```swift
    @State private var autoCheckForUpdates = UpdaterService.shared.automaticallyChecksForUpdates
```

- [ ] **Step 2: Insert the toggle after the version text**

Immediately after `Text("Version \(appVersionString)")` (`SettingsView.swift:610`), add:

```swift
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.top, 10)
                    .onChange(of: autoCheckForUpdates) { _, newValue in
                        UpdaterService.shared.automaticallyChecksForUpdates = newValue
                    }

                if let checked = UpdaterService.shared.lastUpdateCheckDate {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
```

- [ ] **Step 3: Build**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
bash build.sh 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the toggle actually writes through to Sparkle**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
open .build/reshelf.app && sleep 6
```

Open Settings (⌘,), go to About, untick the toggle, quit the app, then:

```bash
defaults read com.kika.opensourceshelf SUEnableAutomaticChecks
```

Expected: `0`. Re-tick it and confirm it reads `1`. If the value never changes, the binding is not reaching `UpdaterService`.

- [ ] **Step 5: Commit**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git add OpenSourceShelf/Views/SettingsView.swift
git commit -m "Settings: automatic update checking toggle in About"
```

---

### Task 6: Rework release.sh for nested signing and two notarization passes

The largest task, and the one that fails loudest if rushed. The current script signs the bundle once and notarizes only the DMG; both assumptions break with an embedded framework.

**Files:**
- Modify: `scripts/release.sh:44-52` (signing block) and `:57-77` (DMG/notarize block)

**Interfaces:**
- Consumes: a built `reshelf.app` containing `Contents/Frameworks/Sparkle.framework`.
- Produces: `.build/dist/reshelf-<version>.zip` (stapled app inside) and `.build/dist/reshelf-<version>.dmg`. Task 7 consumes the ZIP.

- [ ] **Step 1: Replace the signing block with inside-out signing**

Replace the block starting `echo "▶︎ Signing app with Developer ID + hardened runtime…"` — including its now-false comment about there being no embedded frameworks — with:

```bash
echo "▶︎ Signing app inside-out (Sparkle nests a framework + XPC services)…"
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  # Innermost first: signing the outer bundle first invalidates it.
  for inner in \
    "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" \
    "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc" \
    "$SPARKLE_FW/Versions/B/Autoupdate" \
    "$SPARKLE_FW/Versions/B/Updater.app" \
    "$SPARKLE_FW"; do
    [ -e "$inner" ] || continue
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$inner"
  done
fi
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

- [ ] **Step 2: Insert the ZIP notarization pass before DMG creation**

Immediately after the signing block and before `echo "▶︎ Creating DMG…"`, add:

```bash
ZIP="$DIST/$APP_NAME-$VERSION.zip"
echo "▶︎ Notarizing the app (pass 1 of 2, via ZIP)…"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"          # staple the .app, not the zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip so the ticket ships with it
xcrun stapler validate "$APP"
```

- [ ] **Step 3: Update the final summary line to mention both artifacts**

Replace the closing `echo "✅ Done: $DMG"` with:

```bash
echo "✅ Done:"
echo "   DMG (humans):  $DMG"
echo "   ZIP (Sparkle): $ZIP"
```

- [ ] **Step 4: Run the full release**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
RESHELF_SIGN_IDENTITY=ADC1CB6085203C50EB344490FD8FC03345838EFB bash scripts/release.sh
```

Expected: two `status: Accepted` results (one per pass), then both artifacts listed. Budget ~15 minutes. A rejection here almost always means a missed nested component — read the notarytool log URL it prints.

- [ ] **Step 5: Verify the nested signatures and the stapled ticket**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
A=.build/DerivedDataDist/Build/Products/Release/reshelf.app
codesign --verify --deep --strict --verbose=2 "$A"
xcrun stapler validate "$A"
spctl --assess --type execute -vv "$A"
codesign -dvv "$A/Contents/Frameworks/Sparkle.framework" 2>&1 | grep TeamIdentifier
```

Expected: `valid on disk`, `The validate action worked!`, `source=Notarized Developer ID`, and `TeamIdentifier=P5RB3W3D58` on the framework (not Sparkle's own team — that would mean it was never re-signed).

- [ ] **Step 6: Commit**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git add scripts/release.sh
git commit -m "release.sh: inside-out signing and a second notarization pass for Sparkle"
```

---

### Task 7: Add scripts/appcast.sh and publish the feed

**Files:**
- Create: `scripts/appcast.sh`
- Create (on the `gh-pages` branch, via worktree): `appcast.xml`

**Interfaces:**
- Consumes: `.build/dist/reshelf-<version>.zip` from Task 6.
- Produces: a live feed at `https://aka-kika.github.io/reshelf/appcast.xml`.

- [ ] **Step 1: Create the orphan gh-pages branch**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git worktree add --detach .build/pages
cd .build/pages
git checkout --orphan gh-pages
git rm -rf . >/dev/null 2>&1 || true
echo "reshelf update feed" > README.md
git add README.md && git commit -m "Initialise gh-pages for the Sparkle appcast"
git push -u origin gh-pages
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
```

- [ ] **Step 2: Enable Pages on that branch**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
gh api -X POST repos/aka-kika/reshelf/pages -f source[branch]=gh-pages -f source[path]=/ 2>&1 | head -3
```

Expected: JSON describing the Pages site. If it reports the site already exists, that is fine — continue.

- [ ] **Step 3: Write `scripts/appcast.sh`**

```bash
#!/usr/bin/env bash
# Generate the Sparkle appcast from the release ZIP and publish it to gh-pages.
# The EdDSA private key is read from the Keychain by generate_appcast; it is
# never passed on the command line and never printed.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$PROJECT_DIR/.build/dist"
PAGES="$PROJECT_DIR/.build/pages"
TOOLS="${SPARKLE_TOOLS:-$HOME/_KIKA_MAIN/_INFRA/tools/sparkle-2.9.4/bin}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_DIR/OpenSourceShelf/Info.plist")"

[ -f "$DIST/reshelf-$VERSION.zip" ] || { echo "✗ No ZIP for $VERSION — run scripts/release.sh first" >&2; exit 1; }
[ -x "$TOOLS/generate_appcast" ] || { echo "✗ generate_appcast not at $TOOLS" >&2; exit 1; }

# Binaries live on the GitHub Release; only the feed lives on Pages.
DOWNLOAD_PREFIX="https://github.com/aka-kika/reshelf/releases/download/v$VERSION/"

# Release notes: generate_appcast embeds "<basename>.html" sitting next to the
# archive. Pull this version's CHANGELOG section and wrap it as minimal HTML —
# bullets become list items, everything else becomes a paragraph.
echo "▶︎ Rendering release notes…"
awk -v v="## \\[$VERSION\\]" '
  $0 ~ v {inside=1; next}
  inside && /^## \[/ {exit}
  inside {print}
' "$PROJECT_DIR/CHANGELOG.md" | awk '
  BEGIN {print "<html><body>"; inlist=0}
  /^- / {if (!inlist) {print "<ul>"; inlist=1}
         sub(/^- /, ""); gsub(/\*\*/, ""); print "<li>" $0 "</li>"; next}
  /^### / {if (inlist) {print "</ul>"; inlist=0}
           sub(/^### /, ""); print "<h3>" $0 "</h3>"; next}
  /^[[:space:]]*$/ {next}
  {if (inlist) {print "  " $0} else {print "<p>" $0 "</p>"}}
  END {if (inlist) print "</ul>"; print "</body></html>"}
' > "$DIST/reshelf-$VERSION.html"

[ -s "$DIST/reshelf-$VERSION.html" ] || { echo "✗ No CHANGELOG section for $VERSION" >&2; exit 1; }

echo "▶︎ Generating appcast for $VERSION…"
"$TOOLS/generate_appcast" --download-url-prefix "$DOWNLOAD_PREFIX" "$DIST"

echo "▶︎ Publishing to gh-pages…"
git -C "$PROJECT_DIR" worktree add "$PAGES" gh-pages 2>/dev/null || true
git -C "$PAGES" pull --ff-only origin gh-pages
cp "$DIST/appcast.xml" "$PAGES/appcast.xml"
git -C "$PAGES" add appcast.xml
git -C "$PAGES" commit -m "Appcast: $VERSION" || { echo "· no change"; exit 0; }
git -C "$PAGES" push origin gh-pages

echo "✅ Live at https://aka-kika.github.io/reshelf/appcast.xml"
```

- [ ] **Step 4: Run it**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
chmod +x scripts/appcast.sh
bash scripts/appcast.sh
```

Expected: the generation and publish lines, then the live URL.

- [ ] **Step 5: Verify the published feed**

```bash
sleep 60   # Pages takes a moment on first publish
curl -s https://aka-kika.github.io/reshelf/appcast.xml | head -30
```

Expected: XML containing an `<item>` with `sparkle:shortVersionString` of the current version, an `edSignature` attribute, a `<description>` carrying the rendered changelog, and a `url` pointing at `github.com/aka-kika/reshelf/releases/download/`. **No `edSignature` means the Keychain key was not found** — revisit Task 1. An empty `<description>` means the CHANGELOG heading did not match `## [<version>]`.

- [ ] **Step 6: Commit the script**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git add scripts/appcast.sh
git commit -m "Add scripts/appcast.sh publishing the signed feed to gh-pages"
```

---

### Task 8: Ship 1.5.0 and prove the update works

Sparkle cannot be verified with one build — there must be something newer to update *to*. This task ships 1.5.0, then a deliberately trivial 1.5.1, and confirms the update lands.

**Files:**
- Modify: `OpenSourceShelf/Info.plist` (version bumps)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: everything above.
- Produces: a verified update path.

- [ ] **Step 1: Bump to 1.5.0 and write the changelog entry**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.5.0' \
                        -c 'Set :CFBundleVersion 10' OpenSourceShelf/Info.plist
```

Insert this into `CHANGELOG.md` immediately above the `## [1.4.0] — 2026-07-27` line (the appcast's release notes are generated from it, so the `## [1.5.0]` heading must match exactly):

```markdown
## [1.5.0] — 2026-07-28

### Added
- **reshelf updates itself.** New versions arrive in the app instead of as a DMG
  you download and drag. reshelf checks once a day in the background, shows you
  what changed, and installs only when you say so — nothing happens behind your
  back. There's a Check for Updates… item in the reshelf menu for when you're
  impatient, and a switch in Settings ▸ About to turn the automatic checking off.
  Update checks send nothing about your machine.
```

Then:

```bash
git add OpenSourceShelf/Info.plist CHANGELOG.md
git commit -m "Bump to 1.5.0: Sparkle auto-update"
```

- [ ] **Step 2: Build, release, publish the feed, and cut the GitHub Release**

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
RESHELF_SIGN_IDENTITY=ADC1CB6085203C50EB344490FD8FC03345838EFB bash scripts/release.sh
git tag v1.5.0 && git push origin main v1.5.0
gh release create v1.5.0 --title "reshelf 1.5.0" --notes-file <(echo "In-app updates via Sparkle.") \
  --latest .build/dist/reshelf-1.5.0.dmg .build/dist/reshelf-1.5.0.zip
bash scripts/appcast.sh
```

Note the ZIP is attached to the Release too — the appcast's download URLs point at it.

- [ ] **Step 3: Install 1.5.0 by hand on both Macs**

```bash
osascript -e 'quit app "reshelf"'; pkill -x reshelf
MNT=$(hdiutil attach .build/dist/reshelf-1.5.0.dmg -nobrowse -noautoopen | grep -o '/Volumes/.*' | head -1)
rm -rf /Applications/reshelf.app && cp -R "$MNT/reshelf.app" /Applications/reshelf.app
hdiutil detach "$MNT"; open /Applications/reshelf.app
```

This manual step is expected: 1.4.0 has no Sparkle and cannot update itself.

- [ ] **Step 4: Ship a throwaway 1.5.1**

No functional change is needed — the point is having something newer in the feed to update *to*.

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.5.1' \
                        -c 'Set :CFBundleVersion 11' OpenSourceShelf/Info.plist
```

Insert above `## [1.5.0]` in `CHANGELOG.md`:

```markdown
## [1.5.1] — 2026-07-28

### Fixed
- Housekeeping release — verifies the new in-app update path end to end.
```

Then ship it exactly as in Step 2, with the version changed:

```bash
git add OpenSourceShelf/Info.plist CHANGELOG.md
git commit -m "Bump to 1.5.1: verify the update path"
RESHELF_SIGN_IDENTITY=ADC1CB6085203C50EB344490FD8FC03345838EFB bash scripts/release.sh
git tag v1.5.1 && git push origin main v1.5.1
gh release create v1.5.1 --title "reshelf 1.5.1" \
  --notes "Housekeeping release — verifies the in-app update path." \
  --latest .build/dist/reshelf-1.5.1.dmg .build/dist/reshelf-1.5.1.zip
bash scripts/appcast.sh
```

- [ ] **Step 5: Verify the update is offered and installs**

On the second Mac, still running 1.5.0: reshelf ▸ **Check for Updates…**

Expected: Sparkle offers 1.5.1, shows the release notes, installs on approval, and relaunches. Then confirm the catalog survived:

```bash
sqlite3 -readonly ~/reshelf/catalog.store "select count(*) from ZTOOLPROJECT;"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/reshelf.app/Contents/Info.plist
```

Expected: the same project count as before the update, and `1.5.1`. A changed count is the worst possible regression — stop and investigate before shipping anything else.

- [ ] **Step 6: Update the docs**

Tick the Sparkle item in `todo.md`, and change the `future-features.md` line reading `Sparkle auto-update still TODO` to mark it shipped.

```bash
cd /Users/kika_hub/Documents/PROJECTS/01_NOW/reshelf
git add todo.md future-features.md && git commit -m "Docs: Sparkle auto-update shipped in 1.5.0"
```
