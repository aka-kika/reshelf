import Foundation
import SwiftData

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("\(ok ? "PASS" : "FAIL"): \(name)")
    if !ok { failures += 1 }
}

/// Held for the whole run: a context whose container was released traps on its
/// next use, and -O may release a local container after its last mention.
var containers: [ModelContainer] = []

@MainActor
func makeContainer() throws -> ModelContainer {
    let container = try ModelContainer(for: ToolProject.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    containers.append(container)
    return container
}

/// The shape every fixed site follows: capture the id, await, re-fetch, write
/// only to a live row. Returns whether it wrote.
@MainActor
func writeAfterAwait(_ id: UUID, context: ModelContext, during: @MainActor () async -> Void) async -> Bool {
    await during()
    guard let live = LiveProject.fetch(id, in: context) else { return false }
    live.notes = "written after await"
    try? context.save()
    return true
}

@MainActor
func runAll() async throws {
    // 1. A live row is found and the write lands.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "alive")
        context.insert(project)
        try context.save()
        let id = project.id
        let wrote = await writeAfterAwait(id, context: context) { await Task.yield() }
        let reread = LiveProject.fetch(id, in: context)
        check("live row is re-fetched and written", wrote && reread?.notes == "written after await")
        check("isAlive is true for a saved row", LiveProject.isAlive(project))
    }

    // 2. Row deleted and saved during the await: no fetch, no write, no crash.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "gone")
        context.insert(project)
        try context.save()
        let id = project.id
        let wrote = await writeAfterAwait(id, context: context) {
            context.delete(project)
            try? context.save()
        }
        check("row deleted + saved during await: write skipped", !wrote)
        check("row deleted + saved: re-fetch is nil", LiveProject.fetch(id, in: context) == nil)
        check("row deleted + saved: isAlive is false", !LiveProject.isAlive(project))
        let count = (try? context.fetchCount(FetchDescriptor<ToolProject>())) ?? -1
        check("row deleted + saved: store stays empty", count == 0)
    }

    // 3. Row deleted but not saved yet (the delete is still pending).
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "pending")
        context.insert(project)
        try context.save()
        let id = project.id
        context.delete(project)
        check("row deleted, not saved: re-fetch is nil", LiveProject.fetch(id, in: context) == nil)
        check("row deleted, not saved: isAlive is false", !LiveProject.isAlive(project))
    }

    // 4. Row deleted from another context (e.g. a restore) during the await.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "other context")
        context.insert(project)
        try context.save()
        let id = project.id
        let wrote = await writeAfterAwait(id, context: context) {
            let other = ModelContext(container)
            var descriptor = FetchDescriptor<ToolProject>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let row = try? other.fetch(descriptor).first {
                other.delete(row)
                try? other.save()
            }
        }
        check("row deleted from another context: write skipped", !wrote)
    }

    // 5. Refresh-style result list: only rows still alive come back.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let rows = (0..<3).map { ToolProject(name: "repo \($0)") }
        rows.forEach { context.insert($0) }
        try context.save()
        let ids = rows.map(\.id)
        await Task.yield()
        context.delete(rows[1])
        try context.save()
        let live = ids.compactMap { LiveProject.fetch($0, in: context) }
        check("result list holds only live rows", live.map(\.name) == ["repo 0", "repo 2"])
    }

    // 6. Clone completion (ProjectListView.cloneProject): id and name are
    // copied before the await. After the row is deleted, those copies are
    // what the status line uses. Reading the model here would trap.
    do {
        let container = try makeContainer()
        let context = container.mainContext
        let project = ToolProject(name: "while-cloning", githubURL: "https://github.com/acme/one")
        context.insert(project)
        try context.save()
        let id = project.id
        let name = project.name
        let wrote = await writeAfterAwait(id, context: context) {
            context.delete(project)
            try? context.save()
        }
        check("18f0: clone completion does not write a deleted row", !wrote)
        check("18f0: captured name is the one from before the clone", name == "while-cloning")
        check("18f0: captured id no longer fetches a row", LiveProject.fetch(id, in: context) == nil)
    }
}

try await runAll()
exit(failures == 0 ? 0 : 1)
