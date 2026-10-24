#!/bin/bash
# Search matches the GitHub link and the website, so an owner name finds the repo.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/SearchLinks"
mkdir -p "$out"
swiftc -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
