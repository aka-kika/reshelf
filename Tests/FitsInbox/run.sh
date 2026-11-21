#!/bin/bash
# Fits agents checked (22 Nov): lines `shelf.py fits --hide` leaves in
# fits-inbox.jsonl hide the fit like the app's own Hide (her repo matched by
# owner/name, the shelf repo by its GitHub key, any case), after a labelled
# backup; a line for a repo not under My Repos stays, a fit no longer listed
# drops, a failed save keeps the file and leaves the fits shown.
# In-memory stores; the inbox and backups live in a temp folder.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/FitsInbox"
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
    "$app/Services/FitsInbox.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/work"
