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

exit(failures == 0 ? 0 : 1)
