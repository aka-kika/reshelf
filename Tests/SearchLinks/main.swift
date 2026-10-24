import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

let project = ToolProject(name: "Glyph", githubURL: "https://github.com/acme/glyph",
                          websiteURL: "https://glyph.example")
check("an owner matches the GitHub link", project.matchesSearch("acme"))
check("the website host matches", project.matchesSearch("glyph.example"))
check("an unrelated word does not match", !project.matchesSearch("zzzz-not-here"))

if failures > 0 { print("\(failures) failed"); exit(1) }
print("SearchLinks: all passed")
