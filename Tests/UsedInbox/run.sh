#!/bin/bash
# Reshelfed (round 3): lines agents leave in used-inbox.jsonl are applied once
# (repo matched by its GitHub key, project added once in any case), lines for
# repos not on the shelf stay for later, a failed save keeps the file; the UI
# mark and Reshelfed in travel through backups, put-back and duplicate merge.
# In-memory stores; the inbox and backups live in a temp folder.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/UsedInbox"
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
    "$app/Services/UsedInbox.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/work"
