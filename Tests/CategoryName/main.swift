import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

let fromName = CategoryClassifier.classify(language: nil, topics: [], description: "", name: "browser-use")
check("a compound repo name matches its topic: \(fromName)", fromName == "Computer Use")
let spaced = CategoryClassifier.classify(language: nil, topics: [], description: "", name: "Browser Use")
check("a spaced compound name matches too: \(spaced)", spaced == "Computer Use")
let half = CategoryClassifier.classify(language: nil, topics: [], description: "", name: "use")
check("one token of a compound topic is not enough: \(half)", half != "Computer Use")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("CategoryName: all passed")
