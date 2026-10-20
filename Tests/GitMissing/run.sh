#!/bin/bash
# Without Apple's Command Line Tools, /usr/bin/git is a stub that exits
# non-zero: every git command must fail with the plain "needs Command Line
# Tools" error, and git is asked about it only once. Fake git scripts in a
# temp folder; nothing touches ~/reshelf or the network.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/GitMissing"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Services/Git/GitClient.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
