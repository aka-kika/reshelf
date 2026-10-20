#!/bin/bash
# GitHubAuth's Keychain save/delete report their status. Uses a throwaway
# Keychain item (never the app's reshelf.github-token) and deletes it after.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/KeychainSave"
mkdir -p "$out"
swiftc -o "$out/test" \
    "$app/Services/GitHubAuth.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
