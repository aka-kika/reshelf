#!/usr/bin/env bash
# Build a signed, notarized, stapled reshelf.dmg for distribution outside the
# App Store (Developer ID). No secrets in this script:
#   • the signing identity is auto-detected from your Keychain
#   • notarization uses a Keychain credential profile (default: reshelf-notary)
#
# One-time setup before first run:
#   xcrun notarytool store-credentials "reshelf-notary" \
#     --apple-id "<your-apple-id>" --team-id "<TEAMID>" --password "<app-specific-password>"
#
# Then:  bash scripts/release.sh
set -euo pipefail

SCHEME="OpenSource Shelf"
APP_NAME="reshelf"
NOTARY_PROFILE="${RESHELF_NOTARY_PROFILE:-reshelf-notary}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$PROJECT_DIR/.build/DerivedDataDist"
DIST="$PROJECT_DIR/.build/dist"
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

# Auto-detect the Developer ID Application identity from the Keychain.
IDENTITY="${RESHELF_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')}"
if [ -z "$IDENTITY" ]; then
  echo "✗ No 'Developer ID Application' identity found in the Keychain." >&2
  echo "  Create/download one from the Apple Developer portal and install it." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/OpenSourceShelf/Info.plist")"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

echo "▶︎ Identity: $IDENTITY"
echo "▶︎ Version:  $VERSION"
rm -rf "$DIST"; mkdir -p "$DIST"

echo "▶︎ Building universal Release (arm64 + x86_64)…"
xcodebuild -project "$PROJECT_DIR/OpenSourceShelf.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  clean build >/dev/null

echo "▶︎ Signing app with Developer ID + hardened runtime…"
# No embedded frameworks (statically linked) → a single sign of the bundle is enough.
# No --entitlements: the app needs none, and this drops any get-task-allow flag.
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "  $(codesign -dvv "$APP" 2>&1 | grep -E 'TeamIdentifier|Runtime' | tr '\n' ' ')"

echo "▶︎ Creating DMG…"
create-dmg \
  --volname "$APP_NAME $VERSION" \
  --window-size 540 380 --icon-size 110 \
  --icon "$APP_NAME.app" 150 185 \
  --app-drop-link 390 185 \
  --no-internet-enable \
  "$DMG" "$APP" >/dev/null 2>&1 || true
[ -f "$DMG" ] || { echo "✗ DMG creation failed" >&2; exit 1; }

echo "▶︎ Signing DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "▶︎ Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▶︎ Stapling + verifying…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 || true

echo ""
echo "✅ Done: $DMG"
