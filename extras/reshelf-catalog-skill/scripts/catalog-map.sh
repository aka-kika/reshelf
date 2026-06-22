#!/usr/bin/env bash
# Survey the user's WHOLE reshelf shelf — every project they catalogued, whether or
# not it was cloned to disk. Complements scripts/shelf-map.sh from the `reshelf`
# skill (which only sees cloned source). This reads the app's catalog so it can
# surface top-shelf picks the user never downloaded.
#
# Data source (in order):
#   1. Live SwiftData store:  $RESHELF_HOME/catalog.store   (via sqlite3 -json)
#   2. Newest JSON backup:    $RESHELF_HOME/backups/catalog-*.json   (fallback)
#
# Clone status is joined on the GitHub repo slug (URL basename), because the app
# clones each repo into a folder named after that slug, not the catalog name.
#
# Usage:
#   catalog-map.sh                      # summary: totals, by status, the not-cloned gap
#   catalog-map.sh --status topShelf    # rows for one status (topShelf|collector|yardSale)
#   catalog-map.sh --category "AI / Agent"   # rows in one catalog category
#   catalog-map.sh --uncloned           # everything shelved but NOT cloned
#   catalog-map.sh --uncloned --status topShelf   # the classic "did I miss cloning?" view
#   catalog-map.sh --search <term>      # match name/description/tags/category/url
#   catalog-map.sh --tsv                # raw normalized rows (for the agent to filter)
#
# Normalized columns (TSV): cloned  status  category  stars  name  githubURL  shortDescription
set -uo pipefail

RESHELF_HOME="${RESHELF_HOME:-$HOME/reshelf}"
RESHELF_HOME="${RESHELF_HOME/#\~/$HOME}"
STORE="$RESHELF_HOME/catalog.store"

# Clone root can be moved independently of the catalog (app setting).
REPOS="$(defaults read com.kika.opensourceshelf reshelf.cloneRootPath 2>/dev/null || true)"
REPOS="${REPOS:-$RESHELF_HOME/repos}"
REPOS="${REPOS/#\~/$HOME}"

# --- set of cloned repo slugs (lowercased basenames of every clone on disk) -----
CLONED_SLUGS="$(mktemp)"
DATA_JSON="$(mktemp)"
trap 'rm -f "$CLONED_SLUGS" "$DATA_JSON"' EXIT
if [ -d "$REPOS" ]; then
  while IFS= read -r gitdir; do
    basename "$(dirname "$gitdir")" | tr '[:upper:]' '[:lower:]'
  done < <(find "$REPOS" -maxdepth 3 -name .git -type d 2>/dev/null) | sort -u > "$CLONED_SLUGS"
fi

# --- pull the catalog into a JSON file (live store first, then newest backup) ----
SOURCE_LABEL=""
load_data() {
  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$STORE" ]; then
    if sqlite3 -json "$STORE" \
        "SELECT ZSTATUSRAW AS status, ZCATEGORY AS category, ZSTARS AS stars, \
                ZNAME AS name, ZGITHUBURL AS githubURL, ZSHORTDESCRIPTION AS shortDescription, \
                ZLONGDESCRIPTION AS longDescription, ZLICENSE AS license, ZTAGS AS tags \
         FROM ZTOOLPROJECT ORDER BY ZSTATUSRAW, ZCATEGORY, ZNAME;" > "$DATA_JSON" 2>/dev/null \
        && [ -s "$DATA_JSON" ]; then
      SOURCE_LABEL="live catalog.store"
      return 0
    fi
  fi
  local backup
  backup="$(ls -t "$RESHELF_HOME"/backups/catalog-*.json 2>/dev/null | head -1)"
  if [ -n "$backup" ]; then
    cp "$backup" "$DATA_JSON"
    SOURCE_LABEL="JSON backup $(basename "$backup")"
    return 0
  fi
  return 1
}

# --- normalize to clean TSV in python (no bash `read`, so empty fields survive) --
normalized() {
  python3 - "$CLONED_SLUGS" "$DATA_JSON" <<'PY'
import json, sys, os
slugs = set()
with open(sys.argv[1]) as f:
    slugs = {ln.strip() for ln in f if ln.strip()}
data = json.load(open(sys.argv[2]))
rows = data.get("projects", []) if isinstance(data, dict) else data
def g(p, *keys):
    for k in keys:
        v = p.get(k)
        if v not in (None, ""):
            return v
    return ""
def slug_of(url):
    s = str(url).rstrip("/")
    # take the owner/repo, then the repo part; drop tree/blob suffixes and .git
    s = s.split("github.com/")[-1]
    parts = [x for x in s.split("/") if x]
    if len(parts) >= 2:
        repo = parts[1]
    elif parts:
        repo = parts[0]
    else:
        repo = ""
    return repo.replace(".git", "").lower()
def clean(s):
    return str(s).replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()
for p in rows:
    url = g(p, "githubURL", "url")
    cloned = "cloned" if (slug_of(url) and slug_of(url) in slugs) else "—"
    out = [cloned, g(p, "status"), g(p, "category"), str(g(p, "stars")),
           g(p, "name"), url, g(p, "shortDescription", "short")]
    print("\t".join(clean(x) for x in out))
PY
}

print_source() { echo "source: ${SOURCE_LABEL:-none}   clones: $REPOS"; }

fmt_rows() { # pretty one-line-per-repo from normalized TSV on stdin
  awk -F'\t' '{
    mark  = ($1=="cloned") ? "[cloned]" : "[ shelf]"
    stars = ($4=="") ? "-" : $4
    printf "  %s  %-24s  %-14s  \xe2\x98\x85%-7s  %s\n", mark, substr($5,1,24), substr($3,1,14), stars, $6
    if ($7 != "") printf "              %s\n", substr($7,1,98)
  }'
}

summary() {
  print_source; echo
  local data; data="$(normalized)"
  if [ -z "$(printf '%s' "$data" | tr -d '[:space:]')" ]; then
    echo "No projects found in the catalog."
    return 0
  fi
  local total clonedN
  total="$(printf '%s\n' "$data" | grep -c .)"
  clonedN="$(printf '%s\n' "$data" | awk -F'\t' '$1=="cloned"' | grep -c .)"
  echo "Shelf: $total projects catalogued — $clonedN cloned to disk, $((total-clonedN)) shelved-only."
  echo
  echo "By status (cloned / total):"
  printf '%s\n' "$data" | awk -F'\t' '
    { tot[$2]++; if ($1=="cloned") cl[$2]++ }
    END { for (s in tot) printf "  %-12s %d / %d\n", (s==""?"(none)":s), cl[s]+0, tot[s] }' | sort
  echo
  echo "By category (cloned / total):"
  printf '%s\n' "$data" | awk -F'\t' '
    { tot[$3]++; if ($1=="cloned") cl[$3]++ }
    END { for (c in tot) printf "  %-22s %d / %d\n", (c==""?"(uncategorized)":c), cl[c]+0, tot[c] }' | sort
  echo
  echo "Top-shelf picks you have NOT cloned (the gap):"
  local gap; gap="$(printf '%s\n' "$data" | awk -F'\t' '$1!="cloned" && $2=="topShelf"')"
  if [ -z "$gap" ]; then echo "  (none — every top-shelf pick is cloned)"; else printf '%s\n' "$gap" | fmt_rows; fi
  echo
  echo "Next: --status topShelf | --category \"<Cat>\" | --uncloned | --search <term> | --tsv"
}

# --- args ----------------------------------------------------------------------
MODE="summary"; STATUS=""; CATEGORY=""; TERM=""; ONLY_UNCLONED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --status)   MODE="filter"; STATUS="${2:-}"; shift 2 ;;
    --category) MODE="filter"; CATEGORY="${2:-}"; shift 2 ;;
    --uncloned) MODE="filter"; ONLY_UNCLONED=1; shift ;;
    --search)   MODE="filter"; TERM="${2:-}"; shift 2 ;;
    --tsv)      MODE="tsv"; shift ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    *)          MODE="filter"; TERM="$1"; shift ;;
  esac
done

if ! load_data; then
  echo "No catalog found: neither $STORE nor a JSON backup in $RESHELF_HOME/backups/."
  echo "Open the reshelf app at least once so it writes its catalog."
  exit 0
fi

case "$MODE" in
  summary) summary ;;
  tsv)     normalized ;;
  filter)
    print_source; echo
    out="$(normalized)"
    [ -n "$STATUS" ]   && out="$(printf '%s\n' "$out" | awk -F'\t' -v s="$STATUS" '$2==s')"
    [ -n "$CATEGORY" ] && out="$(printf '%s\n' "$out" | awk -F'\t' -v c="$CATEGORY" '$3==c')"
    [ "$ONLY_UNCLONED" = "1" ] && out="$(printf '%s\n' "$out" | awk -F'\t' '$1!="cloned"')"
    [ -n "$TERM" ]     && out="$(printf '%s\n' "$out" | grep -i -- "$TERM")"
    if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
      echo "No matching projects."
    else
      printf '%s\n' "$out" | fmt_rows
      echo
      echo "  ($(printf '%s\n' "$out" | grep -c .) match(es) — [cloned] = on disk, [ shelf] = catalogued only)"
    fi
    ;;
esac
