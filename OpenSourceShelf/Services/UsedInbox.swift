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

    /// One mark `apply` made, so a failed save can take back exactly that.
    struct Mark {
        let project: ToolProject
        let name: String
    }

    /// Marks each entry's repo as used in its project (once per project, any
    /// case). Returns the marks it made and the entries whose repo is not on
    /// the shelf.
    static func apply(_ entries: [Entry], to projects: [ToolProject]) -> (marks: [Mark], unmatched: [Entry]) {
        var byKey: [String: [ToolProject]] = [:]
        for project in projects where !project.githubURL.isEmpty {
            byKey[GitHubRepositoryURL.cachedDedupKey(for: project.githubURL), default: []].append(project)
        }
        var marks: [Mark] = []
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
                marks.append(Mark(project: row, name: entry.project))
            }
        }
        return (marks, unmatched)
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
        var readBytes: [URL: Int] = [:]
        for file in readingFiles {
            let data = (try? Data(contentsOf: file)) ?? Data()
            readBytes[file] = data.count
            entries += parse(String(decoding: data, as: UTF8.self))
        }
        let projects = (try? context.fetch(FetchDescriptor<ToolProject>())) ?? []
        let result = apply(entries, to: projects)
        if !result.marks.isEmpty, !CatalogSave.save(context, "the Reshelfed records") {
            // Not saved: take back only these marks (other unsaved edits stay)
            // and keep the files for next time.
            for mark in result.marks {
                if let i = mark.project.usedIn.lastIndex(of: mark.name) { mark.project.usedIn.remove(at: i) }
            }
            return 0
        }
        // An agent that opened the inbox just before the rename appends to
        // the renamed file: lines after what was read go back to the inbox.
        var keep = result.unmatched
        for file in readingFiles {
            guard let data = try? Data(contentsOf: file), let read = readBytes[file], data.count > read else { continue }
            keep += parse(String(decoding: data.suffix(from: read), as: UTF8.self))
        }
        guard putBack(keep) else { return result.marks.count }
        for file in readingFiles { try? fm.removeItem(at: file) }
        return result.marks.count
    }

    /// Appends entries to the inbox (lines for repos not on the shelf yet).
    @discardableResult
    static func putBack(_ entries: [Entry]) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lines = entries.compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        guard !lines.isEmpty else { return true }
        let text = lines.joined(separator: "\n") + "\n"
        let url = fileURL
        do {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            return true
        } catch {
            return false
        }
    }
}
