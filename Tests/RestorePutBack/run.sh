#!/bin/bash
# Restore from Backup puts back changed repos (undo for Yard Sale moves,
# updating imports, duplicate merges), labelled safety backups, and the
# Remove Duplicate Repos merge. In-memory store; backups go to a temp folder.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/RestorePutBack"
mkdir -p "$out"
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
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/backups"
