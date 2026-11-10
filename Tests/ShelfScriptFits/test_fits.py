"""shelf.py fits: reads the app's saved fits read-only, live store or backup.
Usage: test_fits.py <shelf.py> <work dir> <live reshelf home>"""
import json
import os
import subprocess
import sys

script, work, live = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3]
os.makedirs(work, exist_ok=True)
failures = 0


def fail(msg):
    global failures
    failures += 1
    print("FAIL:", msg)


def run(home, *args, cwd=None):
    env = dict(os.environ, RESHELF_HOME=home, RESHELF_CLONE_ROOT=os.path.join(home, "repos"), HOME=work)
    return subprocess.run([sys.executable, "-I", script, *args], env=env, cwd=cwd,
                          capture_output=True, text=True)


# 1. Live store: the list of her repos.
store = os.path.join(live, "catalog.store")
before = os.path.getmtime(store)
out = run(live, "fits").stdout
if "kika/Sift" not in out or "kika/Kartina" not in out:
    fail("list names both repos: " + out)
if "2 fit(s)" not in out:
    fail("list counts shown fits only (hidden left out): " + out)

# 2. One repo: Top Shelf first, why lines, NEW, license; hidden, Yard Sale and deleted out.
r = run(live, "fits", "Sift")
out = r.stdout
if r.returncode != 0:
    fail("fits Sift failed: " + r.stderr)
if out.find("Top Shelf:") < 0 or out.find("The Collector:") < out.find("Top Shelf:"):
    fail("Top Shelf before The Collector: " + out)
for want in ("Mole", "why: Finds leftover files", "NEW since the run before", "GPL-3.0 - strong copyleft",
             "note: GitHub's limit", "(1 hidden by the user"):
    if want not in out:
        fail(f"'{want}' missing: " + out)
for not_want in ("hiddenone", "gone", "deleted"):
    if not_want in out:
        fail(f"'{not_want}' should be left out: " + out)
if os.path.getmtime(store) != before:
    fail("the store was written to")

# 3. Never-run repo says so and does not match by itself.
out = run(live, "fits", "kartina").stdout
if "has not run yet" not in out:
    fail("never-run repo: " + out)

# 4. Unknown repo: clear message, exit 1.
r = run(live, "fits", "nope")
if r.returncode == 0 or "not under My Repos" not in r.stderr:
    fail("unknown repo: " + r.stdout + r.stderr)

# 5. --here inside a clone of kika/Sift (a local git folder with that origin).
clone = os.path.join(work, "Sift")
os.makedirs(clone, exist_ok=True)
subprocess.run(["git", "init", "-q", clone], check=True)
subprocess.run(["git", "-C", clone, "remote", "add", "origin", "git@github.com:kika/Sift.git"], check=True)
out = run(live, "fits", "--here", cwd=clone).stdout
if "Fits for kika/Sift" not in out:
    fail("--here finds the repo from origin: " + out)
other = os.path.join(work, "other")
os.makedirs(other, exist_ok=True)
subprocess.run(["git", "init", "-q", other], check=True)
subprocess.run(["git", "-C", other, "remote", "add", "origin", "https://github.com/kika/Elsewhere"], check=True)
r = run(live, "fits", "--here", cwd=other)
if r.returncode == 0 or "not under My Repos" not in r.stderr:
    fail("--here in another repo: " + r.stdout + r.stderr)

# 6. No store: the newest backup's myRepos is read.
home2 = os.path.join(work, "backup-home")
os.makedirs(os.path.join(home2, "backups"), exist_ok=True)
json.dump({"projects": [dict(name="Mole", githubURL="https://github.com/tw93/Mole", category="CLI",
                             status="topShelf", license="MIT")],
           "myRepos": [dict(fullName="kika/Sift", githubURL="https://github.com/kika/Sift", summary="",
                            addedAt="2026-11-10T10:00:00Z", sortIndex=0, lastRunAt="2026-11-10T18:40:00Z",
                            lastRunNote="", fits=[dict(repo="tw93/mole", name="Mole", githubURL="",
                                                       shelf="topShelf", rank=0, why="from the backup",
                                                       isNew=False, isHidden=False)])]},
          open(os.path.join(home2, "backups", "catalog-2026-11-10-184000.json"), "w"))
out = run(home2, "fits", "Sift").stdout
if "why: from the backup" not in out or "source: backup" not in out:
    fail("backup fallback: " + out)

# 7. An older catalog without the tables: no My Repos, no crash.
home3 = os.path.join(work, "old-home")
os.makedirs(os.path.join(home3, "backups"), exist_ok=True)
json.dump({"projects": []}, open(os.path.join(home3, "backups", "catalog-2026-01-01.json"), "w"))
r = run(home3, "fits")
if r.returncode != 0 or "No repos under My Repos" not in r.stdout:
    fail("old catalog: " + r.stdout + r.stderr)

print("ShelfScriptFits: all passed" if failures == 0 else f"ShelfScriptFits: {failures} failed")
sys.exit(1 if failures else 0)
