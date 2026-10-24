#!/bin/bash
# The license rule of Refresh Info: GitHub's "no license" / NOASSERTION never
# replaces a license already stored. Pure function; no network.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/RepoLicenseRefresh"
mkdir -p "$out"
rm -f "$out/test"
# Only the GitHubRepoInfo struct (top of the file, before QuickCaptureService)
# is compiled; the rest of the file needs the whole app.
sed -n '1,/^enum QuickCaptureService/p' "$app/Services/QuickCaptureService.swift" | sed '$d' > "$out/GitHubRepoInfo.swift"
grep -q "licenseToStore" "$out/GitHubRepoInfo.swift" || { echo "FAIL: license rule not found"; exit 1; }
swiftc -o "$out/test" "$out/GitHubRepoInfo.swift" "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test"
