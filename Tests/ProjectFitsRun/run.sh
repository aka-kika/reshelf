#!/bin/bash
# Project fits run: her repo list (forks and archived out), the Find Fits run
# against a fake GitHub (READMEs live for the shortlist, rate limit said, hidden
# never picked, nothing-to-match said), Yard Sale and her own repo left out,
# and the shared runner saving the list. No network; in-memory store.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../../OpenSourceShelf"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/ProjectFitsRun"
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
    "$app/Services/GitHubAuth.swift" \
    "$app/Services/LiveProject.swift" \
    "$app/Services/Git/GitClient.swift" \
    "$app/Services/CatalogCloneService.swift" \
    "$app/Services/AppRefresh/AppRefreshBus.swift" \
    "$app/Services/AppRefresh/AppRefreshEvent.swift" \
    "$app/Services/AI/AppleIntelligenceService.swift" \
    "$app/Services/ProjectFits/FitScorer.swift" \
    "$app/Services/ProjectFits/ProjectFitsService.swift" \
    "$app/Services/ProjectFits/ProjectFitsGitHub.swift" \
    "$app/Services/ProjectFits/ProjectFitsRunner.swift" \
    "$here/Stubs.swift" \
    "$here/main.swift" 2>&1 | grep -v "warning:" || true
[ -x "$out/test" ] || { echo "FAIL: build"; exit 1; }
"$out/test" "$out/backups"
