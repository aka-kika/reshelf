#!/bin/bash
# Project fits: the matching rules (cleaning, words, ranking, Top Shelf first,
# nothing-fits), how a new run meets the saved list (hidden stay hidden, new
# gets the dot), and that backups and restores carry My Repos and their fits.
# In-memory stores; backups go to a temp folder.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/ProjectFits"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Models/CatalogFolder.swift" \
    "$app/Models/MyRepo.swift" \
    "$app/Services/CatalogFolderService.swift" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$app/Services/CatalogExportService.swift" \
    "$app/Services/CatalogImportService.swift" \
    "$app/Services/CatalogBackupService.swift" \
    "$app/Services/DuplicateMerge.swift" \
    "$app/Services/CatalogSave.swift" \
    "$app/Services/ProjectFits/FitScorer.swift" \
    "$app/Services/ProjectFits/ProjectFitsService.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/backups"
