import Foundation
import SwiftData

// Writes a real SwiftData catalog (the same tables the app writes) for the
// shelf.py fits test. Usage: make-store <path to catalog.store>
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let schema = Schema([ToolProject.self, CatalogFolder.self, MyRepo.self, RepoFit.self])
let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
let ctx = ModelContext(container)
for (name, link, shelf, license) in [
    ("Mole", "https://github.com/tw93/Mole", ProjectStatus.topShelf, "GPL-3.0"),
    ("uninstally", "https://github.com/x/uninstally", .collector, "MIT"),
    ("gone", "https://github.com/x/gone", .yardSale, "MIT"),
    ("hiddenone", "https://github.com/x/hiddenone", .collector, "MIT"),
] {
    let project = ToolProject(name: name, shortDescription: "\(name) desc", githubURL: link,
                              category: "macOS", status: shelf, license: license)
    // Round 3: the UI mark and Reshelfed in.
    if name == "Mole" { project.likesUI = true }
    if name == "uninstally" { project.usedIn = ["Sift"] }
    ctx.insert(project)
}
ctx.insert(ToolProject(name: "nolicense", githubURL: "https://github.com/x/nolicense", category: "CLI",
                       status: .collector, license: ""))
let sift = MyRepo(fullName: "kika/Sift", githubURL: "https://github.com/kika/Sift", summary: "Scores Mac apps", sortIndex: 0)
sift.lastRunAt = Date(timeIntervalSince1970: 1_762_790_400)
sift.lastRunNote = "GitHub's limit was reached: 3 repos used saved info."
sift.language = "Swift"
ctx.insert(sift)
let fresh = MyRepo(fullName: "kika/Kartina", githubURL: "https://github.com/kika/Kartina", sortIndex: 1)
ctx.insert(fresh)
let mocker = MyRepo(fullName: "kika/Mocker", githubURL: "https://github.com/kika/Mocker", sortIndex: 2)
mocker.lastRunAt = Date(timeIntervalSince1970: 1_762_790_400)
mocker.fitSettingsJSON = #"{"filters":{"hideStrongCopyleft":true},"limit":10}"#
ctx.insert(mocker)
ctx.insert(RepoFit(myRepoID: mocker.id, repoKey: "tw93/mole", rank: 0, why: "gpl one", isNew: false, isHidden: false))
ctx.insert(RepoFit(myRepoID: mocker.id, repoKey: "x/uninstally", rank: 1, why: "mit one", isNew: false, isHidden: false,
                   isPinned: true))
ctx.insert(RepoFit(myRepoID: mocker.id, repoKey: "x/hiddenone", rank: 2, why: "pushed off", isNew: false, isHidden: false,
                   isBumped: true))
for (key, rank, why, new, hidden) in [
    ("x/uninstally", 0, "Dry run before removing", true, false),
    ("tw93/mole", 1, "Finds leftover files after an uninstall", false, false),
    ("x/gone", 2, "moved to Yard Sale after the run", false, false),
    ("x/hiddenone", 3, "hidden by her", false, true),
    ("x/deleted", 4, "row deleted from the catalog", false, false),
] {
    ctx.insert(RepoFit(myRepoID: sift.id, repoKey: key, rank: rank, why: why, isNew: new, isHidden: hidden))
}
try! ctx.save()
