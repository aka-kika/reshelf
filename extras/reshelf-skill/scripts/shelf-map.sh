#!/usr/bin/env bash
# Map the user's reshelf clone library so the agent gets a fast, structured
# picture without reading every file by hand.
#
# Usage:
#   shelf-map.sh                 # list categories with repo counts
#   shelf-map.sh "<Category>"    # detail every repo in one category
#   shelf-map.sh --all           # detail every repo in every category
#
# Note: no `set -e` on purpose — greps/finds that come up empty return non-zero
# and must not abort the map.
set -uo pipefail

# Resolve the clone root. Honor the app's custom Repository Storage setting if the
# user changed it; otherwise fall back to the default.
ROOT="$(defaults read com.kika.opensourceshelf reshelf.cloneRootPath 2>/dev/null || true)"
ROOT="${ROOT:-$HOME/reshelf/repos}"
ROOT="${ROOT/#\~/$HOME}"

if [ ! -d "$ROOT" ]; then
  echo "No reshelf clone folder found at: $ROOT"
  echo "Clone some repos in the reshelf app first (right-click a repo → Clone Repository),"
  echo "or check Settings → Repository Storage for a custom location."
  exit 0
fi

guess_stack() {
  local repo="$1" stack=""
  [ -f "$repo/package.json" ]    && stack="$stack js/ts"
  { [ -f "$repo/pyproject.toml" ] || [ -f "$repo/requirements.txt" ] || [ -f "$repo/setup.py" ]; } && stack="$stack python"
  [ -f "$repo/Cargo.toml" ]      && stack="$stack rust"
  [ -f "$repo/go.mod" ]          && stack="$stack go"
  [ -f "$repo/Package.swift" ]   && stack="$stack swift"
  ls "$repo"/*.xcodeproj >/dev/null 2>&1 && stack="$stack xcode"
  [ -f "$repo/Gemfile" ]         && stack="$stack ruby"
  [ -f "$repo/pom.xml" ]         && stack="$stack java"
  [ -f "$repo/composer.json" ]   && stack="$stack php"
  [ -z "$stack" ] && stack=" ?"
  echo "${stack# }"
}

repo_detail() {
  local repo="$1"
  local name origin last stack readme loc
  name="$(basename "$repo")"
  origin="$(git -C "$repo" config --get remote.origin.url 2>/dev/null || echo '?')"
  last="$(git -C "$repo" log -1 --format='%cd' --date=short 2>/dev/null || echo '?')"
  stack="$(guess_stack "$repo")"
  # Rough size: tracked file count (cheap signal of project scope).
  loc="$(git -C "$repo" ls-files 2>/dev/null | wc -l | tr -d ' ')"
  echo "  • $name"
  echo "      origin:      $origin"
  echo "      last commit: $last    stack: $stack    tracked files: $loc"
  readme="$(ls "$repo"/README* 2>/dev/null | head -1)"
  if [ -n "$readme" ]; then
    echo "      readme:"
    grep -v '^[[:space:]]*$' "$readme" 2>/dev/null | head -8 | sed -e 's/^/        /'
  fi
  echo ""
}

list_categories() {
  echo "reshelf library at: $ROOT"
  echo ""
  echo "Categories (each is a folder of cloned repos):"
  local found=0
  for cat in "$ROOT"/*/; do
    [ -d "$cat" ] || continue
    found=1
    local count
    count="$(find "$cat" -maxdepth 2 -name .git -type d 2>/dev/null | wc -l | tr -d ' ')"
    printf "  %-24s %s repo(s)\n" "$(basename "$cat")" "$count"
  done
  [ "$found" -eq 0 ] && echo "  (none yet — clone some repos in the reshelf app)"
  echo ""
  echo "Next: re-run with a category name to see its repos, e.g.:"
  echo "  bash \"$0\" \"<Category>\""
}

detail_category() {
  local cat="$1"
  local dir="$ROOT/$cat"
  if [ ! -d "$dir" ]; then
    echo "No category folder named '$cat' under $ROOT."
    echo ""
    list_categories
    return
  fi
  echo "Category: $cat   ($dir)"
  echo ""
  local found=0
  for repo in "$dir"/*/; do
    [ -d "$repo/.git" ] || continue
    found=1
    repo_detail "$repo"
  done
  [ "$found" -eq 0 ] && echo "  (no clones in this category yet)"
}

case "${1:-}" in
  "")     list_categories ;;
  --all)
    for cat in "$ROOT"/*/; do
      [ -d "$cat" ] || continue
      detail_category "$(basename "$cat")"
      echo "----------------------------------------"
    done
    ;;
  *)      detail_category "$1" ;;
esac
