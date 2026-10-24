import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS: " : "FAIL: ") + name)
    if !ok { failures += 1 }
}
func expect(_ input: String, _ want: String) {
    let got = WebLink.normalized(input)
    check("\(input.debugDescription) -> \(want.debugDescription) (got \(got.debugDescription))", got == want)
}

// SSH forms become the https link, owner/repo case kept.
expect("git@github.com:Owner/Repo", "https://github.com/Owner/Repo")
expect("git@github.com:Owner/Repo.git", "https://github.com/Owner/Repo")
expect("  git@github.com:owner/repo.git\n", "https://github.com/owner/repo")
expect("ssh://git@github.com/Owner/Repo", "https://github.com/Owner/Repo")
expect("ssh://git@github.com/owner/repo.git", "https://github.com/owner/repo")
// The broken value older builds stored is repaired.
expect("https://git@github.com:Owner/Repo", "https://github.com/Owner/Repo")
expect("https://git@github.com:owner/repo.git", "https://github.com/owner/repo")

// Plain links normalize exactly as before (no churn on saved rows).
expect("https://github.com/Owner/Repo", "https://github.com/Owner/Repo")
expect("https://github.com/owner/repo.git", "https://github.com/owner/repo.git")
expect("https://github.com/owner/repo/tree/main", "https://github.com/owner/repo/tree/main")
expect("http://www.github.com/owner/repo/", "http://www.github.com/owner/repo/")
expect("github.com/owner/repo", "https://github.com/owner/repo")
expect("example.org/docs", "https://example.org/docs")
expect("https://gitlab.com/owner/repo", "https://gitlab.com/owner/repo")
expect("git@gitlab.com:owner/repo.git", "https://git@gitlab.com:owner/repo.git")
expect("ssh://git@gitlab.com/owner/repo", "ssh://git@gitlab.com/owner/repo")
expect("not a link", "not a link")
expect("", "")

// What the link reader makes of each form.
for link in ["git@github.com:Owner/Repo.git", "ssh://git@github.com/Owner/Repo",
             "https://git@github.com:Owner/Repo", "https://github.com/Owner/Repo"] {
    let pair = GitHubRepositoryURL.ownerAndRepo(from: link)
    check("ownerAndRepo(\(link)) = Owner/Repo", pair?.owner == "Owner" && pair?.repo == "Repo")
    check("dedupKey(\(link)) = owner/repo", GitHubRepositoryURL.dedupKey(for: link) == "owner/repo")
}
check("a stored SSH link reads back after normalizing",
      GitHubRepositoryURL.parse(WebLink.normalized("git@github.com:o/r"))?.fullName == "o/r")
check("WebLink.url opens an https URL for an SSH paste",
      WebLink.url("git@github.com:o/r")?.absoluteString == "https://github.com/o/r")
check("WebLink.url opens http",
      WebLink.url("http://example.org/docs")?.scheme == "http")
check("WebLink.url refuses file", WebLink.url("file:///etc/passwd") == nil)
check("WebLink.url refuses smb", WebLink.url("smb://server/share") == nil)
check("WebLink.url refuses a bare path", WebLink.url("/tmp/secret") == nil)
check("WebLink.url refuses an empty link", WebLink.url("   ") == nil)
check("429 is a rate limit", GitHubHTTP.isRateLimited(status: 429, remaining: "10", retryAfter: nil))
check("remaining 0 is a rate limit", GitHubHTTP.isRateLimited(status: 403, remaining: "0", retryAfter: nil))
check("403 with Retry-After is a rate limit", GitHubHTTP.isRateLimited(status: 403, remaining: "30", retryAfter: "60"))
check("403 without Retry-After is not a rate limit",
      !GitHubHTTP.isRateLimited(status: 403, remaining: "30", retryAfter: nil))
check("a blank Retry-After is not a rate limit",
      !GitHubHTTP.isRateLimited(status: 403, remaining: "30", retryAfter: "  "))

if failures > 0 { print("\(failures) failed"); exit(1) }
print("SSHLinks: all passed")
