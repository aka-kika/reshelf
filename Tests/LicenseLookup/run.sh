#!/bin/bash
# License explainer lookup: SPDX ids and full names match by whole words,
# unknown text gets the "read the LICENSE file" card. Components.swift is
# mostly views, so only its license part is cut out and compiled.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/LicenseLookup"
mkdir -p "$out"
{
    echo "import SwiftUI"
    awk '/^\/\/ MARK: - License explainer/{on=1} /^\/\/\/ Small colored pill/{on=0} on' \
        "$app/Views/Components/Components.swift"
} > "$out/License.swift"
grep -q "static func lookup" "$out/License.swift" || { echo "FAIL: license code not found"; exit 1; }
swiftc -o "$out/test" "$out/License.swift" "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test"
