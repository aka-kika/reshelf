#!/bin/bash
# Quick Capture's Save and Fetch stay off until the link reads as a GitHub
# repo (GitHubRepositoryURL.ownerAndRepo): which texts pass and which don't.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/CaptureLinkCheck"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
