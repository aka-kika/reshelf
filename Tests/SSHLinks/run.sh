#!/bin/bash
# A GitHub link pasted the SSH way is stored as https://github.com/owner/repo,
# the broken "https://git@github.com:o/r" older builds stored is repaired, and
# every other link normalizes exactly as before.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/SSHLinks"
mkdir -p "$out"
swiftc -o "$out/test" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
