#!/bin/bash
# GitClient never waits on a login prompt and stops stuck network commands:
# environment (GIT_TERMINAL_PROMPT=0, empty GIT_ASKPASS, no stdin), a plain
# error when git wanted a login, and the time limit. Temp folders only.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/GitClientSafety"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Services/Git/GitClient.swift" \
    "$here/main.swift" || { echo "FAIL: build"; exit 1; }
"$out/test"
