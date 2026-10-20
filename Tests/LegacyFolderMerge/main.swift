import Foundation

let fm = FileManager.default
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? fm.removeItem(at: work)
var failures = 0
func check(_ ok: Bool, _ msg: String, line: Int = #line) {
    if !ok { print("FAIL line \(line): \(msg)"); failures += 1 }
}
func write(_ base: URL, _ path: String, _ text: String) {
    let url = base.appendingPathComponent(path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
}
func read(_ base: URL, _ path: String) -> String? {
    try? String(contentsOf: base.appendingPathComponent(path), encoding: .utf8)
}

// Case 1: both folders exist, overlapping.
let old = work.appendingPathComponent("OpenSourceShelf")
let new = work.appendingPathComponent("reshelf")
write(old, "catalog.store", "old store")
write(old, "catalog.store-wal", "old wal")
write(old, "backups/catalog-1.json", "old b1")
write(old, "backups/catalog-2.json", "old b2")
write(old, "repos/CLI/tool/README", "old tool")
write(old, "repos/CLI/other/README", "old other")
write(old, "repos/Media/player/README", "old player")
write(old, "database/opensource-shelf.sqlite", "old db")
write(old, "notes.txt", "old notes")
write(old, ".DS_Store", "old ds")
write(new, "catalog.store", "new store")
write(new, "backups/catalog-1.json", "new b1")
write(new, "repos/CLI/tool/README", "new tool")
write(new, ".DS_Store", "new ds")

let left = LegacyNameMigration.mergeDataFolder(from: old, into: new)

// Nothing in the new folder was overwritten.
check(read(new, "catalog.store") == "new store", "store overwritten")
check(read(new, "backups/catalog-1.json") == "new b1", "backup overwritten")
check(read(new, "repos/CLI/tool/README") == "new tool", "clone overwritten")
check(read(new, ".DS_Store") == "new ds", ".DS_Store overwritten")
// The store's sidecar never joins someone else's store.
check(read(new, "catalog.store-wal") == nil, "wal moved next to a different store")
// Missing items moved.
check(read(new, "backups/catalog-2.json") == "old b2", "backup 2 not moved")
check(read(new, "repos/CLI/other/README") == "old other", "clone in shared category not moved")
check(read(new, "repos/Media/player/README") == "old player", "new category not moved")
check(read(new, "database/opensource-shelf.sqlite") == "old db", "database not moved")
check(read(new, "notes.txt") == "old notes", "loose file not moved")
// What stayed is still there, untouched.
check(read(old, "catalog.store") == "old store", "old store gone")
check(read(old, "catalog.store-wal") == "old wal", "old wal gone")
check(read(old, "backups/catalog-1.json") == "old b1", "old backup gone")
check(read(old, "repos/CLI/tool/README") == "old tool", "old clone gone")
check(fm.fileExists(atPath: old.path), "old folder removed")
check(left == ["catalog.store", "catalog.store-wal", "backups/catalog-1.json", "repos/CLI/tool"],
      "left behind: \(left)")

let notice = LegacyNameMigration.notice(leftBehind: left) ?? ""
check(!notice.contains("\n"), "notice is more than one line")
check(notice.contains("catalog.store, catalog.store-wal, backups/catalog-1.json and 1 more"), "notice: \(notice)")
check(notice.contains("~/OpenSourceShelf") && notice.contains("Nothing was overwritten or deleted"), "notice: \(notice)")
check(LegacyNameMigration.notice(leftBehind: []) == nil, "notice for nothing left")
check(LegacyNameMigration.notice(leftBehind: ["repos/CLI/tool"])?.contains(": repos/CLI/tool.") == true, "short notice")

// Case 2: the new folder has no store yet: store and sidecars move together.
let old2 = work.appendingPathComponent("old2")
let new2 = work.appendingPathComponent("new2")
write(old2, "catalog.store", "s")
write(old2, "catalog.store-shm", "shm")
write(old2, "repos/CLI/tool/README", "t")
try! fm.createDirectory(at: new2, withIntermediateDirectories: true)
let left2 = LegacyNameMigration.mergeDataFolder(from: old2, into: new2)
check(left2.isEmpty, "left behind: \(left2)")
check(read(new2, "catalog.store") == "s" && read(new2, "catalog.store-shm") == "shm", "store not moved")
check(read(new2, "repos/CLI/tool/README") == "t", "repos not moved")

// Case 3: a file where the new folder has a folder (and the other way) stays put.
let old3 = work.appendingPathComponent("old3")
let new3 = work.appendingPathComponent("new3")
write(old3, "repos", "a file named repos")
write(old3, "backups/x/inner", "nested")
write(new3, "repos/CLI/tool/README", "t")
write(new3, "backups/x", "a file named x")
let left3 = LegacyNameMigration.mergeDataFolder(from: old3, into: new3)
check(left3 == ["backups/x", "repos"], "left behind: \(left3)")
check(read(new3, "backups/x") == "a file named x" && read(old3, "backups/x/inner") == "nested", "type clash touched")

if failures == 0 { print("LegacyFolderMerge: all passed") } else { print("LegacyFolderMerge: \(failures) failed"); exit(1) }
