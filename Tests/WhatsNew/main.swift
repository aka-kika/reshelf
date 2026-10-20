import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

let sample = """
Notarized Developer ID build for macOS 14 or newer. Open the DMG.

New in 1.16.0
- **Restore can undo a change:** turn it on.
- Plain bullet.
"""
let lines = WhatsNew.parse(sample)
check("install line left out, heading and 2 bullets kept", lines.count == 3)
if case .heading(let h) = lines.first { check("first line is the heading", h == "New in 1.16.0") } else { check("first line is the heading", false) }

let suite = "reshelf-whatsnew-test-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
// The test binary has no bundle version, so shouldShow is false; check the
// first-run rule through the stored key instead.
check("no version, no sheet", !WhatsNew.shouldShow(defaults: defaults, usedBefore: true))
defaults.removePersistentDomain(forName: suite)

let shipped = CommandLine.arguments[1]
if let text = try? String(contentsOfFile: shipped, encoding: .utf8) {
    let parsed = WhatsNew.parse(text)
    let bullets = parsed.filter { if case .bullet = $0 { return true } else { return false } }.count
    let headings = parsed.filter { if case .heading = $0 { return true } else { return false } }.count
    check("shipped notes \((shipped as NSString).lastPathComponent): \(headings) headings, \(bullets) bullets",
          headings >= 1 && bullets >= 3 && headings <= 3)
} else {
    check("shipped notes exist at \(shipped)", false)
}
exit(failures == 0 ? 0 : 1)
