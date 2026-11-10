#!/usr/bin/env python3
"""Find repos on your reshelf shelf (Top Shelf first) and clone one on approval.

    shelf.py find <terms...>                 Top Shelf matches (step 1)
    shelf.py find --collector <terms...>     The Collector matches (step 2, only if needed)
    shelf.py find --top                      every Top Shelf repo, recently added first
    shelf.py clone <name-or-github-url>      dry run: shows where it would go + license
    shelf.py clone <name-or-github-url> --yes    actually clone (only after the user said yes)
    shelf.py fits                            the user's own repos under My Repos, with last run
    shelf.py fits <repo>                     the shelf repos that fit one of them, with why
    shelf.py fits --here                     the same for the repo this folder is a clone of

Reads the reshelf app's catalog (live store, or the newest JSON backup) read-only.
Yard Sale is always left out: those repos are on their way out.
`fits` only reads what the app saved the last time the user pressed Find Fits; it
never runs a match itself, and repos the user hid from a list stay out.
Clones exactly like the app does: <clone root>/<Category>/<repo>, falling back to
<owner>-<repo> on a name clash, full clone, git-lfs filters bypassed. A checkout
counts as cloned only with the reshelf marker (.git/reshelf-clone), written when
this script clones. A custom clone folder is never stamped. The app picks the new
clone up the next time its window becomes active.
"""
import glob
import json
import os
import plistlib
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone

HOME = os.path.expanduser("~")
RESHELF_HOME = os.path.expanduser(os.environ.get("RESHELF_HOME", "~/reshelf"))
STORE = os.path.join(RESHELF_HOME, "catalog.store")
# Core Data / SwiftData timestamps count seconds from 2001-01-01 UTC.
APPLE_EPOCH = 978307200


def clone_root():
    # RESHELF_CLONE_ROOT is for tests: it keeps the app's setting out of it.
    if os.environ.get("RESHELF_CLONE_ROOT"):
        return os.path.expanduser(os.environ["RESHELF_CLONE_ROOT"])
    try:
        out = subprocess.run(
            ["defaults", "read", "com.kika.opensourceshelf", "reshelf.cloneRootPath"],
            capture_output=True, text=True).stdout.strip()
    except OSError:
        out = ""
    return os.path.expanduser(out or os.path.join(RESHELF_HOME, "repos"))


# --- catalog -------------------------------------------------------------------

def _archived_strings(blob):
    """SwiftData stores [String] as an NSKeyedArchiver plist."""
    if not blob:
        return []
    try:
        v = plistlib.loads(blob)
    except Exception:
        return []
    if isinstance(v, list):
        return [x for x in v if isinstance(x, str)]
    objs = v.get("$objects", []) if isinstance(v, dict) else []
    return [x for x in objs[1:] if isinstance(x, str)]


def load_catalog():
    if os.path.exists(STORE):
        try:
            db = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
            db.row_factory = sqlite3.Row
            cols = {r[1] for r in db.execute("PRAGMA table_info(ZTOOLPROJECT)")}
            added = "ZADDEDDATE" if "ZADDEDDATE" in cols else "0"
            updated = "ZLASTUPDATEDDATE" if "ZLASTUPDATEDDATE" in cols else "NULL"
            rows = db.execute(f"""SELECT ZNAME, ZSHORTDESCRIPTION, ZLONGDESCRIPTION, ZGITHUBURL,
                ZCATEGORY, ZSTATUSRAW, ZLICENSE, ZSTARS, ZNOTES, ZPERSONALNOTE, ZTAGS, ZUSECASES,
                {added} AS ADDED, {updated} AS UPDATED FROM ZTOOLPROJECT""").fetchall()
            return "live catalog", [dict(
                name=r["ZNAME"] or "", short=r["ZSHORTDESCRIPTION"] or "",
                long=r["ZLONGDESCRIPTION"] or "", url=r["ZGITHUBURL"] or "",
                category=r["ZCATEGORY"] or "", status=r["ZSTATUSRAW"] or "collector",
                license=r["ZLICENSE"] or "", stars=r["ZSTARS"] or "",
                notes=r["ZNOTES"] or "", personal=r["ZPERSONALNOTE"] or "",
                tags=_archived_strings(r["ZTAGS"]), usecases=_archived_strings(r["ZUSECASES"]),
                added=float(r["ADDED"] or 0) + APPLE_EPOCH,
                updated=_apple_time(r["UPDATED"])) for r in rows]
        except sqlite3.Error:
            pass
    backups = sorted(glob.glob(os.path.join(RESHELF_HOME, "backups", "catalog-*.json")),
                     key=os.path.getmtime, reverse=True)
    if not backups:
        sys.exit("No reshelf catalog found. Open the reshelf app once so it writes one.")
    data = json.load(open(backups[0]))
    rows = data.get("projects", []) if isinstance(data, dict) else data
    return f"backup {os.path.basename(backups[0])}", [dict(
        name=p.get("name", ""), short=p.get("shortDescription", ""),
        long=p.get("longDescription", ""), url=p.get("githubURL", ""),
        category=p.get("category", ""), status=p.get("status", "collector"),
        license=p.get("license", ""), stars=p.get("stars", ""), notes=p.get("notes", ""),
        personal=p.get("personalNote", "") or "", tags=p.get("tags", []),
        usecases=p.get("useCases", []), added=_iso_seconds(p.get("addedDate")),
        updated=_iso_seconds(p.get("lastUpdatedDate")) or None) for p in rows]


def _iso_seconds(text):
    """Backup dates are ISO 8601 ("2026-06-23T04:03:49Z"); unknown sorts last."""
    try:
        return datetime.fromisoformat((text or "").replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def _github_name(value):
    """Same rule as the app (GitHubRepositoryURL): GitHub's own characters,
    never "." or "..", which would point a clone at its parent folder."""
    return value not in (".", "..") and re.fullmatch(r"[A-Za-z0-9._-]+", value) is not None


def owner_repo(url):
    m = re.search(r"github\.com[/:]([^/\s]+)/([^/\s#?]+)", url or "")
    if not m:
        return None
    owner, repo = m.group(1), re.sub(r"\.git$", "", m.group(2), flags=re.I)
    if not (_github_name(owner) and _github_name(repo)):
        return None
    return owner, repo


MARKER_NAME = "reshelf-clone"


def marker_path(clone_dir):
    return os.path.join(clone_dir, ".git", MARKER_NAME)


def has_marker(clone_dir):
    return os.path.isfile(marker_path(clone_dir))


def write_marker(clone_dir):
    """Marks a clone this script just made. No-op when .git is not a directory."""
    git_dir = os.path.join(clone_dir, ".git")
    if not os.path.isdir(git_dir) or os.path.exists(marker_path(clone_dir)):
        return
    with open(marker_path(clone_dir), "w") as handle:
        handle.write("reshelf\n")


def _layout_name(folder_name, owner, repo):
    name = folder_name.lower()
    return name == repo.lower() or name == f"{owner}-{repo}".lower()


def _stamps_legacy(root):
    """The default clone folder predates the marker. A custom folder, and the
    RESHELF_CLONE_ROOT test override, must never be stamped."""
    if os.environ.get("RESHELF_CLONE_ROOT"):
        return False
    default = os.path.normpath(os.path.join(RESHELF_HOME, "repos"))
    return os.path.normpath(root) == default


def origin_slug(config_text):
    """(owner, repo) from the origin remote's url in a .git/config, else None.
    Same rule as the app: another remote or a comment naming github.com must
    not decide which repo the folder is."""
    in_origin = False
    for raw in config_text.splitlines():
        line = raw.strip()
        if line.startswith("["):
            in_origin = line.lower() == '[remote "origin"]'
            continue
        if not in_origin or not line.lower().startswith("url") or "=" not in line:
            continue
        url = line.split("=", 1)[1].strip()
        m = re.search(r"github\.com[/:]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", url, re.I)
        return (m.group(1), m.group(2)) if m else None
    return None


def clone_index(root):
    """owner/repo (lowercased) -> clone folder, only for clones reshelf marked."""
    index = {}
    stamp = _stamps_legacy(root)
    for cfg in glob.glob(os.path.join(root, "*", "*", ".git", "config")):
        try:
            text = open(cfg, errors="ignore").read()
        except OSError:
            continue
        found = origin_slug(text)
        if not found:
            continue
        owner, repo = found
        clone_dir = os.path.dirname(os.path.dirname(cfg))
        if not has_marker(clone_dir):
            if not (stamp and _layout_name(os.path.basename(clone_dir), owner, repo)):
                continue
            write_marker(clone_dir)
            if not has_marker(clone_dir):
                continue
        slug = f"{owner}/{repo}".lower()
        if slug not in index:
            index[slug] = clone_dir
    return index


def clone_path(p, index):
    o = owner_repo(p["url"])
    return index.get(f"{o[0]}/{o[1]}".lower()) if o else None


# --- license -------------------------------------------------------------------

def license_note(raw):
    k = (raw or "").strip().lower()
    if k in ("", "none"):
        return "NO LICENSE - study only, do not copy code"
    if k in ("noassertion", "other"):
        return "UNCLEAR LICENSE - read its LICENSE file before reusing code"
    if "agpl" in k:
        return f"{raw} - strong copyleft, even for network use"
    if "lgpl" in k or "mpl" in k or "epl" in k:
        return f"{raw} - weak copyleft"
    if "gpl" in k:
        return f"{raw} - strong copyleft"
    if "busl" in k or "business source" in k:
        return f"{raw} - source-available, not open source"
    return raw


# --- find ----------------------------------------------------------------------

def match_score(p, terms):
    if not terms:
        return 1
    name = p["name"].lower()
    tags = " ".join(p["tags"]).lower()
    text = " ".join([p["short"], p["long"], p["category"], p["notes"],
                     p["personal"], " ".join(p["usecases"])]).lower()
    score = 0
    for t in terms:
        t = t.lower()
        if t in name:
            score += 4
        if t in tags or t == p["category"].lower():
            score += 3
        if t in text:
            score += 1
    return score


def cmd_find(args):
    collector = "--collector" in args
    list_top = "--top" in args
    terms = [a for a in args if not a.startswith("--")]
    if not terms and not list_top:
        sys.exit("Give search terms, or --top to list the whole Top Shelf.")
    source, catalog = load_catalog()
    root = clone_root()
    index = clone_index(root)
    status = "collector" if collector else "topShelf"
    hits = []
    for p in catalog:
        if p["status"] != status:
            continue
        s = match_score(p, terms)
        if s > 0:
            path = clone_path(p, index)
            hits.append((s, p["added"], path is not None, p, path))
    # Best match first; among equal matches, the most recently added.
    hits.sort(key=lambda h: (h[0], h[1], h[2]), reverse=True)

    label = "The Collector" if collector else "Top Shelf"
    print(f"{label}: {len(hits)} match(es)   (source: {source}, clones: {root})\n")
    for s, added, is_cloned, p, path in hits[:25]:
        day = datetime.fromtimestamp(added, timezone.utc).strftime("%Y-%m-%d") if added > APPLE_EPOCH else "?"
        print(f"- {p['name']}  [{p['category'] or 'no category'}]  added {day}  "
              f"{'CLONED' if is_cloned else 'not cloned'}")
        if p["short"]:
            print(f"    {p['short'][:140]}")
        print(f"    {path if path else p['url']}")
        print(f"    license: {license_note(p['license'])}")
        if p["tags"]:
            print(f"    tags: {', '.join(p['tags'][:8])}")
    if len(hits) > 25:
        print(f"\n({len(hits) - 25} more; narrow the terms)")
    if not collector:
        print("\nNothing that fits? Next step: shelf.py find --collector <terms>")


# --- fits (Project fits, saved by the app) ------------------------------------

def _apple_time(value):
    return float(value) + APPLE_EPOCH if value is not None else None


def load_my_repos():
    """The user's repos under My Repos with their saved fits, from the live store
    (tables ZMYREPO, ZREPOFIT) or the newest JSON backup (`myRepos`)."""
    if os.path.exists(STORE):
        try:
            db = sqlite3.connect(f"file:{STORE}?mode=ro", uri=True)
            db.row_factory = sqlite3.Row
            tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if "ZMYREPO" in tables and "ZREPOFIT" in tables:
                repos = []
                cols = {c[1] for c in db.execute("PRAGMA table_info(ZMYREPO)")}
                language = "ZLANGUAGE" if "ZLANGUAGE" in cols else "''"
                own = "ZFITSETTINGSJSON" if "ZFITSETTINGSJSON" in cols else "''"
                fit_cols = {c[1] for c in db.execute("PRAGMA table_info(ZREPOFIT)")}
                kept = "ZISPINNED" if "ZISPINNED" in fit_cols else "0"
                bumped = "ZISBUMPED" if "ZISBUMPED" in fit_cols else "0"
                for r in db.execute(f"""SELECT ZID, ZFULLNAME, ZGITHUBURL, ZSUMMARY, ZLASTRUNAT,
                                       ZLASTRUNNOTE, ZSORTINDEX, {language} AS LANGUAGE, {own} AS OWNFILTER
                                       FROM ZMYREPO ORDER BY ZSORTINDEX, ZFULLNAME"""):
                    fits = [dict(key=f["ZREPOKEY"] or "", rank=f["ZRANK"] or 0, why=f["ZWHY"] or "",
                                 new=bool(f["ZISNEW"]), hidden=bool(f["ZISHIDDEN"]),
                                 kept=bool(f["KEPT"]), made_room=bool(f["BUMPED"]))
                            for f in db.execute(f"""SELECT ZREPOKEY, ZRANK, ZWHY, ZISNEW, ZISHIDDEN,
                                                    {kept} AS KEPT, {bumped} AS BUMPED
                                                    FROM ZREPOFIT WHERE ZMYREPOID = ? ORDER BY ZRANK""",
                                                (r["ZID"],))]
                    repos.append(dict(full=r["ZFULLNAME"] or "", url=r["ZGITHUBURL"] or "",
                                      summary=r["ZSUMMARY"] or "", last=_apple_time(r["ZLASTRUNAT"]),
                                      note=r["ZLASTRUNNOTE"] or "", language=r["LANGUAGE"] or "",
                                      own_filter=r["OWNFILTER"] or "", fits=fits))
                return "live catalog", repos
            if "ZTOOLPROJECT" in tables:
                return "live catalog", []
        except sqlite3.Error:
            pass
    backups = sorted(glob.glob(os.path.join(RESHELF_HOME, "backups", "catalog-*.json")),
                     key=os.path.getmtime, reverse=True)
    if not backups:
        return "no catalog", []
    data = json.load(open(backups[0]))
    rows = data.get("myRepos", []) if isinstance(data, dict) else []
    repos = []
    for r in sorted(rows, key=lambda r: (r.get("sortIndex", 0), r.get("fullName", ""))):
        last = r.get("lastRunAt")
        repos.append(dict(
            full=r.get("fullName", ""), url=r.get("githubURL", ""), summary=r.get("summary", ""),
            last=_iso_seconds(last) if last else None, note=r.get("lastRunNote", ""),
            language=r.get("language") or "", own_filter=r.get("fitSettings") or "",
            fits=[dict(key=f.get("repo", ""), rank=f.get("rank", 0), why=f.get("why", ""),
                       new=bool(f.get("isNew")), hidden=bool(f.get("isHidden")),
                       kept=bool(f.get("isPinned")), made_room=bool(f.get("isBumped")))
                  for f in sorted(r.get("fits", []), key=lambda f: f.get("rank", 0))]))
    return f"backup {os.path.basename(backups[0])}", repos


def _origin_of_cwd():
    try:
        out = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True,
                             text=True, cwd=os.getcwd()).stdout.strip()
    except OSError:
        return None
    return owner_repo(out) if out else None


def _day_time(ts):
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M") if ts else "never"


def _catalog_by_key():
    _, catalog = load_catalog()
    by_key = {}
    for p in catalog:
        o = owner_repo(p["url"])
        if o:
            by_key[f"{o[0]}/{o[1]}".lower()] = p
    return by_key


def _fit_filters():
    """The user's Settings > Fits filters in the app (same for every repo).
    RESHELF_FITS_FILTERS (JSON) is for tests: it keeps the app's settings out."""
    keys = {"sameLanguage": "reshelf.fits.sameLanguage", "updated": "reshelf.fits.updated",
            "hideGPL": "reshelf.fits.hideGPL", "hideArchived": "reshelf.fits.hideArchived",
            "limit": "reshelf.fits.limit"}
    if os.environ.get("RESHELF_FITS_FILTERS"):
        raw = json.loads(os.environ["RESHELF_FITS_FILTERS"])
    else:
        raw = {}
        for name, key in keys.items():
            try:
                raw[name] = subprocess.run(["defaults", "read", "com.kika.opensourceshelf", key],
                                           capture_output=True, text=True).stdout.strip()
            except OSError:
                raw[name] = ""
    on = lambda v: str(v).lower() in ("1", "true", "yes")
    return _filter_dict(on(raw.get("sameLanguage")), str(raw.get("updated", "")), on(raw.get("hideGPL")),
                        on(raw.get("hideArchived")), raw.get("limit"))


LIMITS = (10, 15, 20, 25)


def _filter_dict(same_language, updated, hide_gpl, hide_archived, limit):
    months = {"lastYear": 12, "sixMonths": 6, "threeMonths": 3}.get(updated)
    try:
        limit = int(limit)
    except (TypeError, ValueError):
        limit = 15
    return dict(same_language=bool(same_language), months=months, hide_gpl=bool(hide_gpl),
                hide_archived=bool(hide_archived), limit=limit if limit in LIMITS else 15)


def _own_filter(repo):
    """A repo's own filter (right-click > Filter in the app), or None."""
    try:
        data = json.loads(repo.get("own_filter") or "")
    except ValueError:
        return None
    if not isinstance(data, dict):
        return None
    f = data.get("filters") or {}
    return _filter_dict(f.get("sameLanguage"), str(f.get("updated", "")), f.get("hideStrongCopyleft"),
                        f.get("hideArchived"), data.get("limit"))


def _filter_summary(f):
    parts = []
    if f["same_language"]:
        parts.append("same language only")
    if f["months"]:
        parts.append("updated in the last year" if f["months"] == 12 else f"updated in the last {f['months']} months")
    if f["hide_gpl"]:
        parts.append("no GPL or AGPL")
    if f["hide_archived"]:
        parts.append("no archived repos")
    return (", ".join(parts) or "no filters") + f", at most {f['limit']}"


def _repo_facts():
    """Language, archived flag, last push and licence per owner/repo, from the
    app's GitHub metadata store (read-only). Empty when it is not there."""
    path = os.path.join(RESHELF_HOME, "database", "opensource-shelf.sqlite")
    if not os.path.exists(path):
        return {}
    try:
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        rows = db.execute("""SELECT lower(r.full_name), m.primary_language, m.archived, m.pushed_at,
                             m.license_spdx FROM repositories r
                             JOIN repository_metadata m ON m.repository_id = r.id""").fetchall()
    except sqlite3.Error:
        return {}
    return {k: dict(language=lang or "", archived=bool(arch), pushed=_iso_seconds(pushed) or None,
                    license=lic or "") for k, lang, arch, pushed, lic in rows}


def _passes(filters, repo, p, facts):
    """The app's FitFilters.allows, for one catalog row."""
    f = facts.get(p["key"], {})
    if filters["same_language"] and repo.get("language") and \
            (f.get("language") or "").lower() != repo["language"].lower():
        return False
    if filters["hide_archived"] and f.get("archived"):
        return False
    lic = (p["license"] or f.get("license") or "").upper()
    if filters["hide_gpl"] and "GPL" in lic and "LGPL" not in lic:
        return False
    if filters["months"]:
        when = p.get("updated") or f.get("pushed")
        if not when or when < time.time() - filters["months"] * 30.44 * 86400:
            return False
    return True


def _shown_fits(repo, by_key, filters=None, facts=None):
    """(fit, catalog row) pairs shown for a repo, best fit first (the app lists
    them by fit, whichever shelf), and how many the Fits filters leave out.
    Hidden by the user, gone from the catalog, or since moved to Yard Sale: out."""
    shown, filtered = [], 0
    for f in sorted(repo["fits"], key=lambda f: f["rank"]):
        p = by_key.get(f["key"])
        if f["hidden"] or f.get("made_room") or not p or p["status"] not in ("topShelf", "collector"):
            continue
        if filters and not _passes(filters, repo, dict(p, key=f["key"]), facts or {}):
            filtered += 1
            continue
        shown.append((f, p))
    if filters and len(shown) > filters["limit"]:
        filtered += len(shown) - filters["limit"]
        shown = shown[:filters["limit"]]
    return shown, filtered


def cmd_fits(args):
    here = "--here" in args
    wanted = " ".join(a for a in args if not a.startswith("--")).strip()
    source, repos = load_my_repos()
    if not repos:
        # Also what an older reshelf (no My Repos tables yet) gives.
        print(f"No My Repos yet   (source: {source}).\n"
              "The user adds their own repos in reshelf (the + next to My Repos) and runs "
              "Find Fits there. Nothing to read until then; do not run a match yourself.")
        return
    if not here and not wanted:
        print(f"My Repos: {len(repos)}   (source: {source})\n")
        by_key = _catalog_by_key()
        main, facts = _fit_filters(), _repo_facts()
        for r in repos:
            own = _own_filter(r)
            shown, _ = _shown_fits(r, by_key, own or main, facts)
            print(f"- {r['full']}   last run {_day_time(r['last'])}   {len(shown)} fit(s)"
                  f"{'   own filter' if own else ''}")
            if r["summary"]:
                print(f"    {r['summary'][:140]}")
        print("\nNext: shelf.py fits <repo>   (or --here inside a clone of one of them)")
        return

    if here:
        o = _origin_of_cwd()
        if not o:
            sys.exit("This folder is not a git clone with a GitHub origin.")
        key = f"{o[0]}/{o[1]}".lower()
        repo = next((r for r in repos if r["full"].lower() == key), None)
        if not repo:
            sys.exit(f"{o[0]}/{o[1]} is not under My Repos. The user can add it in reshelf "
                     "(the + next to My Repos).")
    else:
        w = wanted.lower()
        o = owner_repo(wanted)
        repo = next((r for r in repos if r["full"].lower() == w
                     or r["full"].split("/")[-1].lower() == w
                     or (o and r["full"].lower() == f"{o[0]}/{o[1]}".lower())), None)
        if not repo:
            names = ", ".join(r["full"].split("/")[-1] for r in repos) or "none yet"
            sys.exit(f"'{wanted}' is not under My Repos (there: {names}).")

    name = repo["full"].split("/")[-1]
    if repo["last"] is None:
        print(f"{name}: Find Fits has not run yet. It runs only when the user asks, in the "
              "reshelf app (right-click the repo, Find Fits). Do not run a match yourself.")
        return

    by_key = _catalog_by_key()
    index = clone_index(clone_root())
    hidden = sum(1 for f in repo["fits"] if f["hidden"])
    own = _own_filter(repo)
    used = own or _fit_filters()
    shown, filtered = _shown_fits(repo, by_key, used, _repo_facts())

    print(f"Fits for {repo['full']}: {len(shown)}, best fit first   last run {_day_time(repo['last'])}"
          f"   (source: {source})")
    print(f"  filter: {'its own' if own else 'the main one (Settings > Fits)'}: {_filter_summary(used)}")
    if repo["note"]:
        print(f"  note: {repo['note']}")
    if not shown:
        print("\nNothing on the shelf fit it on the last run.")
    else:
        print()
    shelf_names = {"topShelf": "Top Shelf", "collector": "The Collector"}
    for f, p in shown:
        path = clone_path(p, index)
        print(f"- {p['name']}  [{shelf_names[p['status']]} · {p['category'] or 'no category'}]  "
              f"{'CLONED' if path else 'not cloned'}{'  NEW since the run before' if f['new'] else ''}"
              f"{'  KEPT by the user' if f.get('kept') else ''}")
        if f["why"]:
            print(f"    why: {f['why'][:200]}")
        print(f"    {path if path else p['url']}")
        print(f"    license: {license_note(p['license'])}")
    room = [by_key[f["key"]]["name"] for f in repo["fits"]
            if f.get("made_room") and not f["hidden"] and f["key"] in by_key]
    if room:
        print(f"\n({len(room)} older fit(s) made room in the last run, not listed: {', '.join(room)})")
    if hidden:
        print(f"\n({hidden} hidden by the user from this list; not shown)")
    if filtered:
        print(f"({filtered} left out by the Fits filter above; not shown)")
    print("\nThese were saved by the app when the user last pressed Find Fits; they are not refreshed here.")


# --- clone ---------------------------------------------------------------------

def category_folder(category):
    """Same as the app's CatalogCloneService.folderName(forCategory:)."""
    cleaned = " ".join(re.sub(r"[/:\\]", " ", category or "").split())
    # "." or ".." would put clones in the root or above it.
    return "Uncategorized" if cleaned in ("", ".", "..") else cleaned


def cmd_clone(args):
    yes = "--yes" in args
    wanted = " ".join(a for a in args if not a.startswith("--")).strip()
    if not wanted:
        sys.exit("Usage: shelf.py clone <name-or-github-url> [--yes]")
    _, catalog = load_catalog()
    want_or = owner_repo(wanted)
    matches = [p for p in catalog
               if (want_or and owner_repo(p["url"])
                   and "/".join(owner_repo(p["url"])).lower() == "/".join(want_or).lower())
               or p["name"].lower() == wanted.lower()]
    if not matches:
        sys.exit(f"'{wanted}' is not on the shelf. Capture it in the reshelf app first, "
                 "so the catalog stays the one list of what's collected.")
    if len(matches) > 1:
        sys.exit("More than one repo matches: " + ", ".join(p["url"] for p in matches)
                 + ". Pass the GitHub URL instead.")
    p = matches[0]
    o = owner_repo(p["url"])
    if not o:
        sys.exit(f"{p['name']} has no usable GitHub URL ({p['url'] or 'none'}), so there is nothing to clone.")
    if p["status"] == "yardSale":
        sys.exit(f"{p['name']} is in the Yard Sale. Move it back to a shelf in the app first.")
    root = clone_root()
    existing = clone_index(root).get("/".join(o).lower())
    if existing:
        print(f"Already cloned: {existing}")
        return
    folder = os.path.join(root, category_folder(p["category"]))
    dest = None
    for name in (o[1], f"{o[0]}-{o[1]}"):
        candidate = os.path.join(folder, name)
        if not os.path.exists(candidate) or not [f for f in os.listdir(candidate) if f != ".DS_Store"]:
            dest = candidate
            break
    if dest is None:
        sys.exit(f"Both {o[1]} and {o[0]}-{o[1]} are taken in {folder}. Sort it out in the app.")
    # Never clone (or clear a leftover folder) anywhere but <root>/<Category>/<repo>.
    if os.path.dirname(os.path.dirname(os.path.normpath(dest))) != os.path.normpath(root):
        sys.exit(f"Refusing to clone outside {root}: {dest}")

    print(f"Repo:     {p['name']}  ({p['status']})")
    print(f"From:     https://github.com/{o[0]}/{o[1]}")
    print(f"To:       {dest}")
    print(f"License:  {license_note(p['license'])}")
    if not yes:
        print("\nDry run. Nothing cloned. Ask the user, then run again with --yes.")
        return
    if os.path.isdir(dest):  # empty leftover folder (or only .DS_Store): git needs it gone
        for f in os.listdir(dest):
            os.remove(os.path.join(dest, f))
        os.rmdir(dest)
    os.makedirs(folder, exist_ok=True)
    lfs = ["-c", "filter.lfs.smudge=", "-c", "filter.lfs.clean=",
           "-c", "filter.lfs.process=", "-c", "filter.lfs.required=false"]
    result = subprocess.run(["git", *lfs, "clone", f"https://github.com/{o[0]}/{o[1]}", dest])
    if result.returncode != 0:
        sys.exit("git clone failed (see above).")
    write_marker(dest)
    print(f"\nCloned. The reshelf app shows it as cloned next time its window is active.")


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "find":
        cmd_find(args)
    elif cmd == "clone":
        cmd_clone(args)
    elif cmd == "fits":
        cmd_fits(args)
    else:
        sys.exit(f"Unknown command '{cmd}'. Use find, fits or clone.")


if __name__ == "__main__":
    main()
