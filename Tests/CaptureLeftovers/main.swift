import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

// The form after the first repo, when the second fetch starts.
let before = CaptureLeftovers(useCases: "first uses", notes: "first note", personalNote: "first why",
                              isSelfHosted: true, isLocalFirst: false)

let untouched = before.cleared(from: before)
check("the first repo's use cases, note and why are cleared (0598)",
      untouched.useCases.isEmpty && untouched.notes.isEmpty && untouched.personalNote.isEmpty)
check("the first repo's flags are cleared", !untouched.isSelfHosted && !untouched.isLocalFirst)

var typed = before
typed.notes = "typed during the fetch"
typed.personalNote = "first why, and more"
typed.isLocalFirst = true
let kept = before.cleared(from: typed)
check("a note typed during the fetch is kept", kept.notes == "typed during the fetch")
check("an edited why is kept", kept.personalNote == "first why, and more")
check("a flag ticked during the fetch is kept", kept.isLocalFirst)
check("fields left alone are still cleared", kept.useCases.isEmpty && !kept.isSelfHosted)

if failures > 0 { print("\(failures) failed"); exit(1) }
print("CaptureLeftovers: all passed")
