#!/bin/bash
# An odd category name cannot walk shelf-map.sh outside the clone folder.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../../extras/reshelf-skill/scripts/shelf-map.sh"
work="$(mktemp -d -t reshelf-shelf-map)"
trap 'rm -rf "$work"' EXIT
root="$work/repos"
outside="$work/outside-secret"
mkdir -p "$root/CLI/tool" "$outside"
printf 'keep\n' > "$outside/secret.txt"

out="$(RESHELF_CLONE_ROOT="$root" bash "$script" '../outside-secret')"
printf '%s\n' "$out" | grep -q "$outside" && { echo "FAIL: escaped: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'secret.txt' && { echo "FAIL: read outside: $out"; exit 1; }

out="$(RESHELF_CLONE_ROOT="$root" bash "$script" '..')"
printf '%s\n' "$out" | grep -q "$work/outside" && { echo "FAIL: .. walked out: $out"; exit 1; }

# A real category still lists.
out="$(RESHELF_CLONE_ROOT="$root" bash "$script" 'CLI')"
printf '%s\n' "$out" | grep -q 'CLI' || { echo "FAIL: CLI missing: $out"; exit 1; }
echo "ShelfMap: all passed"
