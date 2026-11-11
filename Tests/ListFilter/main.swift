import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

func repo(_ name: String, ui: Bool = false) -> ToolProject {
    let p = ToolProject(name: name, githubURL: "https://github.com/o/\(name)")
    p.likesUI = ui
    return p
}

let projects = [repo("a"), repo("b", ui: true), repo("c"), repo("d", ui: true), repo("e"), repo("nolang", ui: true),
                ToolProject(name: "nolink")]
let facts: [String: RepoFacts] = [
    "o/a": RepoFacts(language: "Swift"), "o/b": RepoFacts(language: "Swift"), "o/c": RepoFacts(language: "swift"),
    "o/d": RepoFacts(language: "TypeScript"), "o/e": RepoFacts(language: "Rust"),
]

let counts = ListFilter.counts(projects, facts: facts)
check("languages counted, most first, case folded", counts.map(\.name) == ["Swift", "Rust", "TypeScript"]
      && counts.first?.count == 3)
check("the picked spelling is kept for the tick", ListFilter.counts(projects, facts: facts, keeping: "swift").first?.name == "swift")
check("unknown language not listed", !counts.contains { $0.name.isEmpty })
let kept = ListFilter.counts(projects, facts: facts, keeping: "Go")
check("the picked language stays in the menu with 0", kept.last?.name == "Go" && kept.last?.count == 0)

check("no filter keeps every row", ListFilter().apply(projects, facts: facts).count == projects.count)
check("Swift (any case)", ListFilter(language: "SWIFT").apply(projects, facts: facts).map(\.name) == ["a", "b", "c"])
check("UI only", ListFilter(uiOnly: true).apply(projects, facts: facts).map(\.name) == ["b", "d", "nolang"])
check("both", ListFilter(language: "Swift", uiOnly: true).apply(projects, facts: facts).map(\.name) == ["b"])
check("title", ListFilter(language: "Swift", uiOnly: true).title == "Swift · UI" && ListFilter(uiOnly: true).title == "UI")
check("active only when set", !ListFilter().isActive && ListFilter(language: "Go").isActive)

// Review: one pass gives the same answers as the separate ones.
let one = ListFilter(language: "Swift", uiOnly: true).evaluate(projects, facts: facts)
check("one pass: visible", one.visible.map(\.name) == ["b"])
check("one pass: languages among UI-marked repos", one.languages.map(\.name) == ["Swift", "TypeScript"]
      && one.languages.first?.count == 1)
check("one pass: UI count among Swift repos", one.uiCount == 1)
let plain = ListFilter().evaluate(projects, facts: facts)
check("one pass, no filter: same as counts", plain.languages.map(\.name) == counts.map(\.name)
      && plain.uiCount == 3 && plain.visible.count == projects.count)

exit(failures == 0 ? 0 : 1)
