#!/bin/bash
# The reshelf skill's shelf.py uses the app's name rules: a category of "." or
# ".." goes to Uncategorized, an owner or repo of "." or ".." is refused. Runs
# against a temp reshelf home and clone root, with a fake git (no network).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
out="${TEST_BUILD_DIR:-$(mktemp -d -t reshelf-tests)}/ShelfScriptNames"
mkdir -p "$out"
python3 -I "$here/test_shelf.py" "$here/../../extras/reshelf-skill/scripts/shelf.py" "$out"
