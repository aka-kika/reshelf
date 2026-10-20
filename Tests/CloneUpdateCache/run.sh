#!/bin/bash
# The per-session update-check cache (reused on reselect, replaced by Check,
# Pull and the list's sweeps), Remove Local Clone with no clone, and the
# clone-folder helpers Settings uses. Real git repos in a temp folder; the
# "GitHub" origin is redirected to a local repo, so there is no network and
# nothing touches ~/reshelf.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/CloneUpdateCache"
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
