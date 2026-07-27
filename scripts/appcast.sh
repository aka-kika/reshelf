#!/usr/bin/env bash
# Generate the Sparkle appcast from the release ZIP and publish it to gh-pages.
#
# The EdDSA private key is read from the Keychain by generate_appcast — it is
# never passed on the command line, written to the repo, or printed.
#
# Run after scripts/release.sh has produced .build/dist/reshelf-<version>.zip,
# and after the GitHub Release for that version exists (the feed's download URLs
# point at the Release assets, not at Pages).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$PROJECT_DIR/.build/dist"
# generate_appcast refuses a directory holding two archives of the same bundle
# version, and we ship both a ZIP and a DMG. Stage only the ZIP (the artifact
# Sparkle actually downloads) plus its release notes.
STAGE="$PROJECT_DIR/.build/appcast-src"
PAGES="$PROJECT_DIR/.build/pages"
TOOLS="${SPARKLE_TOOLS:-$HOME/_KIKA_MAIN/_INFRA/tools/sparkle-2.9.4/bin}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$PROJECT_DIR/OpenSourceShelf/Info.plist")"

[ -f "$DIST/reshelf-$VERSION.zip" ] || {
  echo "✗ No ZIP for $VERSION — run scripts/release.sh first" >&2; exit 1; }
[ -x "$TOOLS/generate_appcast" ] || {
  echo "✗ generate_appcast not found at $TOOLS" >&2
  echo "  Set SPARKLE_TOOLS, or unpack the Sparkle release tarball there." >&2; exit 1; }

# Binaries live on the GitHub Release; only the feed lives on Pages.
DOWNLOAD_PREFIX="https://github.com/aka-kika/reshelf/releases/download/v$VERSION/"

# Stage the ZIP on its own. Kept across runs so generate_appcast can carry
# forward entries for older versions already in the feed.
mkdir -p "$STAGE"
cp -f "$DIST/reshelf-$VERSION.zip" "$STAGE/"

# Release notes: generate_appcast embeds "<archive-basename>.html" if it sits
# beside the archive. Pull this version's CHANGELOG section and wrap it as
# minimal HTML — bullets become list items, everything else a paragraph.
echo "▶︎ Rendering release notes for $VERSION…"
# Literal prefix match, not a regex: awk -v collapses backslash escapes, so a
# quoted "## \[1.5.0\]" degrades into the character class [1.5.0] and matches
# nothing useful. index() sidesteps the whole problem.
awk -v want="## [$VERSION]" '
  index($0, want) == 1 {inside = 1; next}
  inside && /^## \[/ {exit}
  inside {print}
' "$PROJECT_DIR/CHANGELOG.md" | awk '
  BEGIN {print "<html><body>"; inlist = 0}
  /^- / {if (!inlist) {print "<ul>"; inlist = 1}
         sub(/^- /, ""); gsub(/\*\*/, ""); print "<li>" $0 "</li>"; next}
  /^### / {if (inlist) {print "</ul>"; inlist = 0}
           sub(/^### /, ""); print "<h3>" $0 "</h3>"; next}
  /^[[:space:]]*$/ {next}
  {gsub(/\*\*/, "")
   if (inlist) {print "  " $0} else {print "<p>" $0 "</p>"}}
  END {if (inlist) print "</ul>"; print "</body></html>"}
' > "$STAGE/reshelf-$VERSION.html"

grep -q "<li>\|<p>" "$STAGE/reshelf-$VERSION.html" || {
  echo "✗ No CHANGELOG section found for $VERSION (expected a '## [$VERSION]' heading)" >&2
  exit 1; }

echo "▶︎ Generating appcast…"
"$TOOLS/generate_appcast" --download-url-prefix "$DOWNLOAD_PREFIX" "$STAGE"
[ -f "$STAGE/appcast.xml" ] || { echo "✗ generate_appcast produced no appcast.xml" >&2; exit 1; }
grep -q 'edSignature' "$STAGE/appcast.xml" || {
  echo "✗ appcast has no edSignature — the Keychain key was not found" >&2; exit 1; }

echo "▶︎ Publishing to gh-pages…"
git -C "$PROJECT_DIR" worktree add "$PAGES" gh-pages 2>/dev/null || true
git -C "$PAGES" pull --ff-only origin gh-pages
# The feed's releaseNotesLink points at Pages, so the rendered notes must ship
# alongside it — publishing appcast.xml alone leaves every entry linking to a 404.
cp "$STAGE/appcast.xml" "$PAGES/appcast.xml"
cp "$STAGE"/reshelf-*.html "$PAGES/"
git -C "$PAGES" add appcast.xml reshelf-*.html
if git -C "$PAGES" diff --cached --quiet; then
  echo "· appcast unchanged — nothing to publish"
  exit 0
fi
git -C "$PAGES" commit -q -m "Appcast: $VERSION"
git -C "$PAGES" push -q origin gh-pages

echo ""
echo "✅ Live at https://aka-kika.github.io/reshelf/appcast.xml"
