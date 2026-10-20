#!/bin/bash
# ~/OpenSourceShelf merging into an existing ~/reshelf: missing items move,
# nothing is overwritten or deleted, and the notice names what stayed. The
# migration is cut out of OpenSourceShelfApp.swift (the rest is the app
# itself) and run on temp folders only.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/LegacyFolderMerge"
mkdir -p "$out"
{
    echo "import Foundation"
    awk '/^\/\/\/ One-time migration from the app/{on=1} /^\/\/\/ Resolves the SwiftData catalog store/{on=0} on' \
        "$app/OpenSourceShelfApp.swift"
} > "$out/Migration.swift"
grep -q "static func mergeDataFolder" "$out/Migration.swift" || { echo "FAIL: migration code not found"; exit 1; }
swiftc -o "$out/test" "$out/Migration.swift" "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/folders"
