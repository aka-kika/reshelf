#!/bin/bash
# The reshelf skill's `shelf.py fits` reads My Repos and their saved fits from a
# real SwiftData store (made here with the app's models) or the newest backup,
# read-only: best fit first with the shelf per row, why lines, NEW, Fits filters,
# hidden / Yard Sale / deleted left
# out, --here from the folder's origin, a never-run repo says so.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
base="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}"
mkdir -p "$base"
out="$(mktemp -d "$base/ShelfScriptFits.XXXXXX")"
mkdir -p "$out/live"
swiftc -o "$out/make-store" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Models/CatalogFolder.swift" \
    "$app/Models/MyRepo.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/make-store" ] || { echo "FAIL: build"; exit 1; }
"$out/make-store" "$out/live/catalog.store"
python3 -I "$here/test_fits.py" "$here/../../extras/reshelf-skill/scripts/shelf.py" "$out/work" "$out/live"
