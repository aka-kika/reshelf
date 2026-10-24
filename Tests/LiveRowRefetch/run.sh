#!/bin/bash
# LiveProject: async paths re-fetch a ToolProject by id after an await and
# skip the write when the row was deleted meanwhile (crash fix, 2026-10-20).
# Compiles the model + helper with this main.swift; in-memory store only.
# Case 18f0 runs the real CatalogCloneService.clone against a local upstream
# (git's insteadOf maps github.com to a temp folder): no network, no ~/reshelf.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/LiveRowRefetch"
mkdir -p "$out"
rm -f "$out/test"
swiftc -O -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Services/LiveProject.swift" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$app/Services/Git/GitClient.swift" \
    "$app/Services/CatalogCloneService.swift" \
    "$app/Services/AppRefresh/AppRefreshBus.swift" \
    "$app/Services/AppRefresh/AppRefreshEvent.swift" \
    "$here/../CloneIndexLayout/Stubs.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test"
