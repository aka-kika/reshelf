import Foundation

// A refresh never replaces a hand-typed license with "none" or NOASSERTION.
var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { print("PASS \(name)") } else { failures += 1; print("FAIL \(name): got \"\(got)\", want \"\(want)\"") }
}
let f = GitHubRepoInfo.licenseToStore
check("5dbc: hand-typed kept when GitHub has no license", f("Custom EULA", ""), "Custom EULA")
check("5dbc: hand-typed kept on NOASSERTION", f("Custom EULA", "NOASSERTION"), "Custom EULA")
check("5dbc: a real GitHub license wins", f("Custom EULA", "MIT"), "MIT")
check("5dbc: a license name wins", f("", "Some Name"), "Some Name")
check("5dbc: empty takes NOASSERTION like capture", f("", "NOASSERTION"), "NOASSERTION")
check("5dbc: empty stays empty", f("", ""), "")
check("5dbc: blank counts as empty", f("  ", "MIT"), "MIT")
if failures > 0 { exit(1) }
