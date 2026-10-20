#!/bin/bash
# Routine backups wait for the catalog to sit still (a bulk import writes one
# snapshot, not one per repo); labelled safety backups and the quit backup are
# written at once. The Restore list reads counts and labels off the main thread.
# In-memory store; backups go to a temp folder.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/BackupDebounce"
mkdir -p "$out"
rm -f "$out/test"
swiftc -o "$out/test" \
    "$app/Models/ToolProject.swift" \
    "$app/Models/ProjectStatus.swift" \
    "$app/Models/CatalogFolder.swift" \
    "$app/Services/CatalogFolderService.swift" \
    "$app/Services/Ingestion/GitHubRepositoryURL.swift" \
    "$app/Services/CatalogExportService.swift" \
    "$app/Services/CatalogImportService.swift" \
    "$app/Services/CatalogBackupService.swift" \
    "$app/Services/DuplicateMerge.swift" \
    "$app/Services/CatalogSave.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/backups"
