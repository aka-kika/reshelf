#!/bin/bash
# Icon size math and resize (fits inside 64 x 64, thread-safe drawing) and the
# memory of failed avatar downloads. Pure logic, no network, no SwiftUI.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/IconFetch"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Services/IconRules.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test"
