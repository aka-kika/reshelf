import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}

// The same test Quick Capture's isRepoLink makes.
func canSave(_ text: String) -> Bool { GitHubRepositoryURL.ownerAndRepo(from: text) != nil }

for text in ["https://github.com/owner/repo",
             "github.com/owner/repo",
             "  https://www.github.com/owner/repo/  ",
             "https://github.com/owner/repo/tree/main/src",
             "https://github.com/owner/repo.git",
             "git@github.com:owner/repo.git"] {
    check("Save allowed: \(text)", canSave(text))
}
for text in ["", "   ", "hello world", "my notes about a repo",
             "https://gitlab.com/owner/repo",
             "https://example.com/owner/repo",
             "https://github.com/owner",
             "https://github.com/"] {
    check("Save off: \"\(text)\"", !canSave(text))
}
exit(failures == 0 ? 0 : 1)
