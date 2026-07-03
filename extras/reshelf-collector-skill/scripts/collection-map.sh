#!/usr/bin/env bash
# Survey the KEEPER side of the user's reshelf shelf — everything catalogued
# EXCEPT the Yard Sale — leading with The Collector: the shelved-and-forgotten
# middle that is neither promoted to Top Shelf nor cloned to disk.
# Completes the trio: shelf-map.sh (`reshelf`) sees cloned source,
# catalog-map.sh (`reshelf-catalog`) sees the whole index; THIS one resurfaces
# the rest. Yard Sale rows are always excluded — that shelf is on its way out.
#
# Data source (in order):
#   1. Live SwiftData store:  $RESHELF_HOME/catalog.store   (via sqlite3 -json)
#   2. Newest JSON backup:    $RESHELF_HOME/backups/catalog-*.json   (fallback)
#
# Clone status is joined on the GitHub repo slug (URL basename), because the app
# clones each repo into a folder named after that slug, not the catalog name.
#
# Usage:
#   collection-map.sh                     # summary: totals + the forgotten-middle list
#   collection-map.sh --status collector  # rows for one status (collector|topShelf)
#   collection-map.sh --category "AI / Agent"   # rows in one catalog category
#   collection-map.sh --uncloned          # kept, but not on disk
#   collection-map.sh --oldest            # the whole collection, longest-shelved first
#   collection-map.sh --search <term>     # match name/desc/tags/category/url
#   collection-map.sh --tsv               # raw normalized rows (for the agent to filter)
#
# Normalized columns (TSV): cloned  status  category  stars  added  name  githubURL  shortDescription
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
                ZADDEDDATE AS addedDate, ZNAME AS name, ZGITHUBURL AS githubURL, \
                ZSHORTDESCRIPTION AS shortDescription, ZLICENSE AS license, ZTAGS AS tags \
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

# --- normalize to clean TSV in python (yardSale dropped; collector listed first) --
normalized() {
  python3 - "$CLONED_SLUGS" "$DATA_JSON" <<'PY'
import datetime, json, sys
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
    s = s.split("github.com/")[-1]
    parts = [x for x in s.split("/") if x]
    repo = parts[1] if len(parts) >= 2 else (parts[0] if parts else "")
    return repo.replace(".git", "").lower()
def added_month(v):
    # Live store: Core Data epoch (seconds since 2001-01-01). Backups: ISO 8601.
    try:
        ts = float(v)
        return datetime.datetime.fromtimestamp(ts + 978307200, datetime.timezone.utc).strftime("%Y-%m")
    except (TypeError, ValueError):
        return str(v)[:7] if v else ""
def clean(s):
    return str(s).replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()
keep = [p for p in rows if g(p, "status") != "yardSale"]
# The Collector leads — it's the shelf this skill exists to resurface.
keep.sort(key=lambda p: (g(p, "status") != "collector", g(p, "category"), str(g(p, "name")).lower()))
for p in keep:
    url = g(p, "githubURL", "url")
    cloned = "cloned" if (slug_of(url) and slug_of(url) in slugs) else "—"
    out = [cloned, g(p, "status"), g(p, "category"), str(g(p, "stars")),
           added_month(g(p, "addedDate")), g(p, "name"), url, g(p, "shortDescription", "short")]
    print("\t".join(clean(x) for x in out))
PY
}

print_source() { echo "source: ${SOURCE_LABEL:-none}   clones: $REPOS   (Yard Sale excluded)"; }

fmt_rows() { # pretty one-line-per-repo from normalized TSV on stdin
  awk -F'\t' '{
    mark  = ($1=="cloned") ? "[cloned]" : "[ shelf]"
    stars = ($4=="") ? "-" : $4
    added = ($5=="") ? "?" : $5
    printf "  %s  %-24s  %-14s  \xe2\x98\x85%-7s  added %s  %s\n", mark, substr($6,1,24), substr($3,1,14), stars, added, $7
    if ($8 != "") printf "              %s\n", substr($8,1,98)
  }'
}

summary() {
  print_source; echo
  local data; data="$(normalized)"
  if [ -z "$(printf '%s' "$data" | tr -d '[:space:]')" ]; then
    echo "No projects found in the collection."
    return 0
  fi
  local total clonedN
  total="$(printf '%s\n' "$data" | grep -c .)"
  clonedN="$(printf '%s\n' "$data" | awk -F'\t' '$1=="cloned"' | grep -c .)"
  echo "Collection (Yard Sale excluded): $total projects — $clonedN cloned, $((total-clonedN)) shelved-only."
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
  echo "The forgotten middle — Collector picks, not cloned, longest-shelved first:"
  local mid
  mid="$(printf '%s\n' "$data" | awk -F'\t' '$1!="cloned" && $2=="collector"' | sort -t"$(printf '\t')" -k5,5 | head -12)"
  if [ -z "$mid" ]; then echo "  (none — every Collector pick is on disk)"; else printf '%s\n' "$mid" | fmt_rows; fi
  echo
  echo "Next: --status collector | --category \"<Cat>\" | --uncloned | --oldest | --search <term> | --tsv"
}

# --- args ----------------------------------------------------------------------
MODE="summary"; STATUS=""; CATEGORY=""; TERM=""; ONLY_UNCLONED=0; OLDEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --status)   MODE="filter"; STATUS="${2:-}"; shift 2 ;;
    --category) MODE="filter"; CATEGORY="${2:-}"; shift 2 ;;
    --uncloned) MODE="filter"; ONLY_UNCLONED=1; shift ;;
    --oldest)   MODE="filter"; OLDEST=1; shift ;;
    --search)   MODE="filter"; TERM="${2:-}"; shift 2 ;;
    --tsv)      MODE="tsv"; shift ;;
    -h|--help)  sed -n '2,26p' "$0"; exit 0 ;;
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
    [ "$OLDEST" = "1" ]        && out="$(printf '%s\n' "$out" | sort -t"$(printf '\t')" -k5,5)"
    [ -n "$TERM" ]     && out="$(printf '%s\n' "$out" | grep -i -- "$TERM")"
    if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
      echo "No matching projects (remember: Yard Sale is excluded here)."
    else
      printf '%s\n' "$out" | fmt_rows
      echo
      echo "  ($(printf '%s\n' "$out" | grep -c .) match(es) — [cloned] = on disk, [ shelf] = catalogued only)"
    fi
    ;;
esac
