#!/bin/bash
# Live clones folder: which FSEvents paths count (category level and a
# clone's .git), and a real FSEvents round trip in a temp folder: a new
# clone folder, then one deleted, each give one coalesced rescan. Never ~/reshelf.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/CloneFolderWatch"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Services/LiveProject.swift" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$app/Services/Git/GitClient.swift" \
    "$app/Services/CatalogCloneService.swift" \
    "$app/Services/AppRefresh/AppRefreshBus.swift" \
    "$app/Services/AppRefresh/AppRefreshEvent.swift" \
    "$here/Stubs.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test"
