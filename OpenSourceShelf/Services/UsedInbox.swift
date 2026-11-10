import Foundation
import SwiftData

/// "Used in <project>" from agents (round 3, Kika 11 Nov). When an agent
/// borrows code from a shelf repo, the reshelf skill's `shelf.py used` writes
/// the thank-you line into the project's ACKNOWLEDGEMENTS.md and adds one JSON
/// line here: `{"repo": "owner/name", "project": "Localpen", "what": "…", "at": "…"}`.
///
/// The app owns the catalog, so agents never write the store: reshelf reads
/// this file at launch and whenever it comes to the front, marks the repos,
/// saves (which also backs up) and removes what it applied. A line for a repo
/// that is not on the shelf stays in the file until it is.
enum UsedInbox {
    struct Entry: Codable, Equatable {
        var repo: String
        var project: String
        var what: String?
        var at: String?
    }

    /// Tests point this at a temp file.
    static var fileOverride: URL?

    static var fileURL: URL {
        fileOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("reshelf", isDirectory: true)
            .appendingPathComponent("used-inbox.jsonl")
    }

    /// One entry per readable line; blank or broken lines are skipped.
    static func parse(_ text: String) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)) else { return nil }
            let repo = entry.repo.trimmingCharacters(in: .whitespaces)
            let project = entry.project.trimmingCharacters(in: .whitespaces)
            guard !repo.isEmpty, !project.isEmpty else { return nil }
            return Entry(repo: repo, project: project, what: entry.what, at: entry.at)
        }
    }

    /// Marks each entry's repo as used in its project (once per project, any
    /// case). Returns how many marks are new and the entries whose repo is not
    /// on the shelf.
    static func apply(_ entries: [Entry], to projects: [ToolProject]) -> (added: Int, unmatched: [Entry]) {
        var byKey: [String: [ToolProject]] = [:]
        for project in projects where !project.githubURL.isEmpty {
            byKey[GitHubRepositoryURL.dedupKey(for: project.githubURL), default: []].append(project)
        }
        var added = 0
        var unmatched: [Entry] = []
        for entry in entries {
            let link = entry.repo.contains("/") && !entry.repo.contains("://")
                ? "https://github.com/" + entry.repo : entry.repo
            guard let rows = byKey[GitHubRepositoryURL.dedupKey(for: link)], !rows.isEmpty else {
                unmatched.append(entry)
                continue
            }
            for row in rows where !row.isUsed(in: entry.project) {
                row.usedIn.append(entry.project)
                added += 1
            }
        }
        return (added, unmatched)
    }

    /// Reads and applies the file. The file is renamed first, so a line an
    /// agent adds meanwhile lands in a new file and is read next time; a
    /// renamed file left by a crash is read too.
    @MainActor
    @discardableResult
    static func drain(in context: ModelContext) -> Int {
        let fm = FileManager.default
        let inbox = fileURL
        let folder = inbox.deletingLastPathComponent()
        let stem = inbox.deletingPathExtension().lastPathComponent
        if fm.fileExists(atPath: inbox.path) {
            let reading = folder.appendingPathComponent("\(stem).\(UUID().uuidString).reading")
            try? fm.moveItem(at: inbox, to: reading)
        }
        let readingFiles = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(stem + ".") && $0.pathExtension == "reading" }
        guard !readingFiles.isEmpty else { return 0 }

        var entries: [Entry] = []
        for file in readingFiles {
            entries += parse((try? String(contentsOf: file, encoding: .utf8)) ?? "")
        }
        let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        let result = apply(entries, to: projects)
        if result.added > 0, !CatalogSave.save(context, "the Used in records") {
            // Not saved: undo the marks and keep the files for next time.
            context.rollback()
            return 0
        }
        if !result.unmatched.isEmpty { putBack(result.unmatched) }
        for file in readingFiles { try? fm.removeItem(at: file) }
        return result.added
    }

    /// Appends entries to the inbox (lines for repos not on the shelf yet).
    static func putBack(_ entries: [Entry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lines = entries.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n") + "\n"
        let url = fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
        }
    }
}
