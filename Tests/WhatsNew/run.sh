#!/bin/bash
# What's new: parsing the release notes, once-after-update logic, and that
# the shipped notes for the current version parse.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/WhatsNew"
mkdir -p "$out"
swiftc -o "$out/test" "$app/Views/WhatsNew.swift" "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Info.plist")
"$out/test" "$here/../../docs/release-notes/$version.md"
