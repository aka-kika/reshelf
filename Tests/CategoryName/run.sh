#!/bin/bash
# A repo named browser-use is Computer Use even with no topics.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/CategoryName"
mkdir -p "$out"
swiftc -o "$out/test" \
    "$app/Services/CategoryClassifier.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
