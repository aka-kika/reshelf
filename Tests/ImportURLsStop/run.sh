#!/bin/bash
# Bulk URL import stops at the first GitHub rate-limit answer and when Stop is
# pressed, keeps what it saved, and hands back the links it didn't get to.
# Compiles the real sheet file with stubs for the GitHub client.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/ImportURLsStop"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Models/CatalogFolder.swift" \
    "$app/Services/CatalogSave.swift" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$app/Services/CategoryClassifier.swift" \
    "$app/Services/GitHubDate.swift" \
    "$app/Services/GitHubAuth.swift" \
    "$app/Views/ImportURLsSheet.swift" \
    "$here/Stubs.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test"
