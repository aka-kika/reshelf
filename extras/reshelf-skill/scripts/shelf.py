#!/usr/bin/env python3
"""Find repos on your reshelf shelf (Top Shelf first) and clone one on approval.

    shelf.py find <terms...>                 Top Shelf matches (step 1)
    shelf.py find --collector <terms...>     The Collector matches (step 2, only if needed)
    shelf.py find --top                      every Top Shelf repo, recently added first
    shelf.py clone <name-or-github-url>      dry run: shows where it would go + license
    shelf.py clone <name-or-github-url> --yes    actually clone (only after the user said yes)

Reads the reshelf app's catalog (live store, or the newest JSON backup) read-only.
Yard Sale is always left out: those repos are on their way out.
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
            rows = db.execute(f"""SELECT ZNAME, ZSHORTDESCRIPTION, ZLONGDESCRIPTION, ZGITHUBURL,
                ZCATEGORY, ZSTATUSRAW, ZLICENSE, ZSTARS, ZNOTES, ZPERSONALNOTE, ZTAGS, ZUSECASES,
                {added} AS ADDED FROM ZTOOLPROJECT""").fetchall()
            return "live catalog", [dict(
                name=r["ZNAME"] or "", short=r["ZSHORTDESCRIPTION"] or "",
                long=r["ZLONGDESCRIPTION"] or "", url=r["ZGITHUBURL"] or "",
                category=r["ZCATEGORY"] or "", status=r["ZSTATUSRAW"] or "collector",
                license=r["ZLICENSE"] or "", stars=r["ZSTARS"] or "",
                notes=r["ZNOTES"] or "", personal=r["ZPERSONALNOTE"] or "",
                tags=_archived_strings(r["ZTAGS"]), usecases=_archived_strings(r["ZUSECASES"]),
                added=float(r["ADDED"] or 0) + APPLE_EPOCH) for r in rows]
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
        usecases=p.get("useCases", []), added=_iso_seconds(p.get("addedDate"))) for p in rows]


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
    else:
        sys.exit(f"Unknown command '{cmd}'. Use find or clone.")


if __name__ == "__main__":
    main()
