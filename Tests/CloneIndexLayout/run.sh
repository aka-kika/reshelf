#!/bin/bash
# The clone index only adopts finished checkouts at reshelf's own layout,
# <root>/<Category>/<repo> or <root>/<Category>/<owner>-<repo>. Builds real
# git repos in a temp folder; never reads the real clone folder (~/reshelf).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/CloneIndexLayout"
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
