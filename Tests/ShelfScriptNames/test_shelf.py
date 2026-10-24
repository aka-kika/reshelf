"""shelf.py name rules, in a temp home. Usage: test_shelf.py <shelf.py> <work dir>"""
import json
import os
import shutil
import subprocess
import sys

script, work = sys.argv[1], os.path.abspath(sys.argv[2])
shutil.rmtree(work, ignore_errors=True)
home = os.path.join(work, "reshelf")
root = os.path.join(home, "repos")
fakebin = os.path.join(work, "bin")
log = os.path.join(work, "git.log")
os.makedirs(os.path.join(home, "backups"))
os.makedirs(root)
os.makedirs(fakebin)
open(os.path.join(home, "catalog-marker.txt"), "w").write("keep me")

# Fake git: records the call and makes the destination folder.
with open(os.path.join(fakebin, "git"), "w") as f:
    f.write('#!/bin/bash\necho "$@" >> "%s"\nfor last; do :; done\nmkdir -p "$last"\n' % log)
os.chmod(os.path.join(fakebin, "git"), 0o755)

projects = [
    ("dotdot-cat", "https://github.com/acme/one", ".."),
    ("dot-cat", "https://github.com/acme/two", "."),
    ("spaces-cat", "https://github.com/acme/three", "  ..  "),
    ("empty-cat", "https://github.com/acme/four", ""),
    ("slash-cat", "https://github.com/acme/five", "AI / Agent"),
    ("bad-owner", "https://github.com/../six", "CLI"),
    ("bad-owner-dot", "https://github.com/./seven", "CLI"),
    ("bad-repo", "https://github.com/acme/..", "CLI"),
    ("bad-repo-dot", "https://github.com/acme/.", "CLI"),
    ("bad-repo-git", "https://github.com/acme/..git", "CLI"),
    ("bad-chars", "https://github.com/acme/we%27ird", "CLI"),
]
json.dump({"projects": [dict(name=n, githubURL=u, category=c, status="topShelf")
                        for n, u, c in projects]},
          open(os.path.join(home, "backups", "catalog-2026-10-20.json"), "w"))

env = dict(os.environ, RESHELF_HOME=home, RESHELF_CLONE_ROOT=root, HOME=work,
           PATH=fakebin + os.pathsep + os.environ.get("PATH", ""))
failures = 0


def run(*args):
    return subprocess.run([sys.executable, "-I", script, *args], env=env,
                          capture_output=True, text=True)


def fail(msg):
    global failures
    failures += 1
    print("FAIL:", msg)


def git_calls():
    return open(log).read().count("clone") if os.path.exists(log) else 0


# Category "." / ".." / empty: Uncategorized, like the app.
for name, repo, folder in [("dotdot-cat", "one", "Uncategorized"), ("dot-cat", "two", "Uncategorized"),
                           ("spaces-cat", "three", "Uncategorized"), ("empty-cat", "four", "Uncategorized"),
                           ("slash-cat", "five", "AI Agent")]:
    want = os.path.join(root, folder, repo)
    r = run("clone", name)
    if r.returncode != 0 or f"To:       {want}\n" not in r.stdout:
        fail(f"{name} dry run: {r.stdout}{r.stderr}")
    r = run("clone", name, "--yes")
    if r.returncode != 0 or not os.path.isdir(want):
        fail(f"{name} --yes did not clone into {want}: {r.stdout}{r.stderr}")

# Owner or repo "." / "..": refused, git never runs.
before = git_calls()
for name in ["bad-owner", "bad-owner-dot", "bad-repo", "bad-repo-dot", "bad-repo-git", "bad-chars"]:
    r = run("clone", name, "--yes")
    if r.returncode == 0 or "no usable GitHub URL" not in r.stderr:
        fail(f"{name} not refused: {r.stdout}{r.stderr}")
for link in ["https://github.com/../six", "https://github.com/acme/.."]:
    r = run("clone", link, "--yes")
    if r.returncode == 0:
        fail(f"{link} not refused: {r.stdout}")
if git_calls() != before:
    fail("git ran for a refused name")

# Nothing landed beside the catalog or above the clone root.
if sorted(os.listdir(home)) != ["backups", "catalog-marker.txt", "repos"]:
    fail(f"reshelf home changed: {sorted(os.listdir(home))}")
if sorted(os.listdir(root)) != ["AI Agent", "Uncategorized"]:
    fail(f"clone root has: {sorted(os.listdir(root))}")
if sorted(os.listdir(work)) != ["bin", "git.log", "reshelf"]:
    fail(f"work dir has: {sorted(os.listdir(work))}")

# find still lists every row (bad links just show as not cloned).
r = run("find", "--top")
if r.returncode != 0 or "11 match(es)" not in r.stdout:
    fail(f"find --top: {r.stdout}{r.stderr}")

# A layout checkout with no marker is not a clone. RESHELF_CLONE_ROOT is set,
# so the script must not stamp it. The marker makes it count.
foreign = os.path.join(root, "Work", "one")
os.makedirs(os.path.join(foreign, ".git"))
with open(os.path.join(foreign, ".git", "config"), "w") as f:
    f.write('[remote "origin"]\n\turl = https://github.com/acme/one.git\n')
r = run("find", "--top")
if r.returncode != 0 or "CLONED" in r.stdout:
    fail(f"unmarked checkout counted as cloned: {r.stdout}{r.stderr}")
if os.path.exists(os.path.join(foreign, ".git", "reshelf-clone")):
    fail("custom clone folder was stamped")
with open(os.path.join(foreign, ".git", "reshelf-clone"), "w") as f:
    f.write("reshelf\n")
r = run("find", "dotdot-cat")
if r.returncode != 0 or "CLONED" not in r.stdout or foreign not in r.stdout:
    fail(f"marked checkout not cloned: {r.stdout}{r.stderr}")

# Only the origin remote names the clone (146706e): another remote or a
# comment with a github.com link comes first in this config.
decoy = os.path.join(root, "Work", "two")
os.makedirs(os.path.join(decoy, ".git"))
with open(os.path.join(decoy, ".git", "config"), "w") as f:
    f.write('[core]\n\tcomment = see github.com/acme/one\n'
            '[remote "upstream"]\n\turl = https://github.com/acme/one.git\n'
            '[remote "origin"]\n\turl = git@github.com:acme/two.git\n')
with open(os.path.join(decoy, ".git", "reshelf-clone"), "w") as f:
    f.write("reshelf\n")
r = run("find", "dot-cat")
if r.returncode != 0 or decoy not in r.stdout:
    fail(f"origin remote did not decide the clone: {r.stdout}{r.stderr}")
r = run("find", "dotdot-cat")
if decoy in r.stdout:
    fail(f"a non-origin remote decided the clone: {r.stdout}")

if failures:
    print(f"ShelfScriptNames: {failures} failed")
    sys.exit(1)
print("ShelfScriptNames: all passed")
