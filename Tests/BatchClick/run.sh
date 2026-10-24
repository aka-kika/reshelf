#!/bin/bash
# A plain click, then a command-click, puts both rows in the batch.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/BatchClick"
mkdir -p "$out"
swiftc -o "$out/test" \
    "$app/Models/ProjectStatus.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
