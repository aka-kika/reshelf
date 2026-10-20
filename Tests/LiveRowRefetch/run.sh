#!/bin/bash
# LiveProject: async paths re-fetch a ToolProject by id after an await and
# skip the write when the row was deleted meanwhile (crash fix, 2026-10-20).
# Compiles the model + helper with this main.swift; in-memory store only.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/LiveRowRefetch"
mkdir -p "$out"
rm -f "$out/test"
swiftc -O -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Services/LiveProject.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
