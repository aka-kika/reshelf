import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

// 1. Which paths count.
let r = "/Users/k/reshelf/repos"
check("the root counts", CloneFolderWatcher.isRelevant(r, root: r) && CloneFolderWatcher.isRelevant(r + "/", root: r))
check("a category folder counts (a clone folder came or went)", CloneFolderWatcher.isRelevant(r + "/macOS/", root: r))
check("a clone's .git counts (the marker lands there)", CloneFolderWatcher.isRelevant(r + "/macOS/cortex/.git", root: r))
check("files inside a clone do not count",
      !CloneFolderWatcher.isRelevant(r + "/macOS/cortex/Sources", root: r)
      && !CloneFolderWatcher.isRelevant(r + "/macOS/cortex/.git/objects", root: r)
      && !CloneFolderWatcher.isRelevant(r + "/macOS/cortex", root: r))
check("outside the root does not count", !CloneFolderWatcher.isRelevant("/Users/k/reshelf/backups", root: r)
      && !CloneFolderWatcher.isRelevant("/Users/k/reshelf/repos-old/macOS", root: r))

// 2. A real round trip: one rescan per burst, after it settles.
let fm = FileManager.default
let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reshelf-watch-\(UUID().uuidString)")
let root = base.appendingPathComponent("repos")
try! fm.createDirectory(at: root.appendingPathComponent("macOS"), withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }

var calls = 0
let watcher = CloneFolderWatcher()
watcher.settle = 0.3
watcher.start(root: root) { calls += 1 }
check("watching", watcher.isRunning)

func waitFor(_ seconds: Double, until done: () -> Bool) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end, !done() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}
// FSEvents needs a moment before it reports events from "now".
waitFor(1.0) { false }
let clone = root.appendingPathComponent("macOS/newrepo/.git")
try! fm.createDirectory(at: clone, withIntermediateDirectories: true)
for i in 0..<20 { try! "x".write(to: clone.appendingPathComponent("f\(i)"), atomically: false, encoding: .utf8) }
try! "".write(to: clone.appendingPathComponent("reshelf-clone"), atomically: false, encoding: .utf8)
waitFor(6) { calls > 0 }
check("a new clone folder gives a rescan", calls >= 1)
waitFor(1.5) { false }
check("a burst of writes gives one rescan, not twenty", calls <= 2)
// d135: once the marker is there and seen, git status, a fetch or an editor
// writing in .git do not rescan the whole root again.
let settled = calls
for i in 0..<5 {
    try! "x".write(to: clone.appendingPathComponent("index"), atomically: true, encoding: .utf8)
    try! "y\(i)".write(to: clone.appendingPathComponent("FETCH_HEAD"), atomically: false, encoding: .utf8)
    waitFor(0.4) { false }
}
waitFor(2.0) { false }
check("d135: writes in a marked clone's .git give no rescan", calls == settled)
var seen = Set<String>()
let unmarked = base.appendingPathComponent("plain/.git")
try! fm.createDirectory(at: unmarked, withIntermediateDirectories: true)
check("d135: an unmarked clone's .git always counts",
      CloneFolderWatcher.countsGitWrite(gitDir: unmarked, seen: &seen)
      && CloneFolderWatcher.countsGitWrite(gitDir: unmarked, seen: &seen))
try! "".write(to: unmarked.appendingPathComponent("reshelf-clone"), atomically: false, encoding: .utf8)
check("d135: the marker counts once when it shows up",
      CloneFolderWatcher.countsGitWrite(gitDir: unmarked, seen: &seen)
      && !CloneFolderWatcher.countsGitWrite(gitDir: unmarked, seen: &seen))
let before = calls
try! fm.removeItem(at: root.appendingPathComponent("macOS/newrepo"))
waitFor(6) { calls > before }
check("a deleted clone folder gives a rescan", calls > before)
watcher.stop()
check("stopped", !watcher.isRunning)
let afterStop = calls
try! fm.createDirectory(at: root.appendingPathComponent("CLI/other"), withIntermediateDirectories: true)
waitFor(2.5) { false }
check("no rescans while stopped (app hidden)", calls == afterStop)

// 3. Build 41 review: a clones folder that does not exist yet is watched
//    once it appears (fresh install, an unplugged drive).
let later = base.appendingPathComponent("later-repos")
var laterCalls = 0
let waitingWatcher = CloneFolderWatcher()
waitingWatcher.settle = 0.3
waitingWatcher.start(root: later) { laterCalls += 1 }
check("missing folder: not running, waiting", !waitingWatcher.isRunning && waitingWatcher.isWaiting)
waitingWatcher.startIfWaiting()
check("still waiting while the folder is missing", !waitingWatcher.isRunning)
try! fm.createDirectory(at: later, withIntermediateDirectories: true)
waitingWatcher.startIfWaiting()
check("starts once the folder exists", waitingWatcher.isRunning && !waitingWatcher.isWaiting)
waitFor(0.5) { false }
try! fm.createDirectory(at: later.appendingPathComponent("macOS/first"), withIntermediateDirectories: true)
waitFor(6) { laterCalls > 0 }
check("and sees the first clone", laterCalls > 0)
waitingWatcher.stop()
waitingWatcher.start(root: base.appendingPathComponent("gone")) {}
waitingWatcher.stop()
check("stop (app hidden) forgets the wait", !waitingWatcher.isWaiting)

exit(failures == 0 ? 0 : 1)
