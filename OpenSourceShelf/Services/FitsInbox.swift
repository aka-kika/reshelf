import Foundation
import SwiftData

/// Fits agents checked (Kika, 21-22 Nov: "remove fits from the my repos fits
/// after they check them ... so next session its not reading same fits
/// again"). After reading one of her repos' fits, the reshelf skill's
/// `shelf.py fits <repo> --hide <name>` (or `--used`) adds one JSON line here:
/// `{"myRepo": "owner/name", "repo": "owner/name", "action": "hide", "name": "…", "at": "…"}`.
///
/// Agents never write the store: reshelf reads this file at launch and
/// whenever it comes to the front, does what its own "Hide from <repo> Fits"
/// does (`RepoFit.isHidden`), after a labelled backup, and removes what it
/// applied. A line for a repo not under My Repos stays until it is; a line
/// for a fit that is no longer on the list has nothing left to hide and goes.
/// Same file handling as `UsedInbox`.
enum FitsInbox {
    struct Entry: Codable, Equatable {
        var myRepo: String
        var repo: String
        var action: String?
        var name: String?
        var at: String?
    }

    /// Tests point this at a temp file.
    static var fileOverride: URL?

    static var fileURL: URL {
        fileOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("reshelf", isDirectory: true)
            .appendingPathComponent("fits-inbox.jsonl")
    }

    /// One entry per readable hide line; blank, broken or other lines are skipped.
    static func parse(_ text: String) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)) else { return nil }
            let mine = entry.myRepo.trimmingCharacters(in: .whitespaces)
            let repo = entry.repo.trimmingCharacters(in: .whitespaces)
            guard !mine.isEmpty, !repo.isEmpty, (entry.action ?? "hide") == "hide" else { return nil }
            return Entry(myRepo: mine, repo: repo, action: "hide", name: entry.name, at: entry.at)
        }
    }

    /// The fits a line names: her repo by `owner/name` (any case), the shelf
    /// repo by its GitHub key. Returns the fits still to hide, and the entries
    /// whose repo is not under My Repos.
    static func match(_ entries: [Entry], repos: [MyRepo], fits: [RepoFit]) -> (hide: [RepoFit], unmatched: [Entry]) {
        var repoIDs: [String: UUID] = [:]
        for repo in repos { repoIDs[repo.fullName.lowercased()] = repo.id }
        var byRepo: [UUID: [String: RepoFit]] = [:]
        for fit in fits { byRepo[fit.myRepoID, default: [:]][fit.repoKey] = fit }
        var hide: [RepoFit] = []
        var seen = Set<ObjectIdentifier>()
        var unmatched: [Entry] = []
        for entry in entries {
            guard let id = repoIDs[entry.myRepo.lowercased()] else {
                unmatched.append(entry)
                continue
            }
            let link = entry.repo.contains("/") && !entry.repo.contains("://")
                ? "https://github.com/" + entry.repo : entry.repo
            guard let fit = byRepo[id]?[GitHubRepositoryURL.dedupKey(for: link)], !fit.isHidden,
                  seen.insert(ObjectIdentifier(fit)).inserted else { continue }
            hide.append(fit)
        }
        return (hide, unmatched)
    }

    /// Reads and applies the file; returns how many fits it hid. The file is
    /// renamed first, so a line an agent adds meanwhile lands in a new file
    /// and is read next time; a renamed file left by a crash is read too.
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
        let result = match(entries, repos: ProjectFitsService.repos(in: context),
                           fits: (try? context.fetch(FetchDescriptor<RepoFit>())) ?? [])
        if !result.hide.isEmpty {
            // The undo point, like other changes made for her in bulk.
            let count = result.hide.count
            guard CatalogBackupService.writeSnapshot(
                from: context, reason: "Before hiding \(count) fit\(count == 1 ? "" : "s") agents checked")
            else { return 0 }
            for fit in result.hide { fit.isHidden = true }
            guard CatalogSave.save(context, "the fits agents hid") else {
                // Not saved: take back only these (other unsaved edits stay)
                // and keep the files for next time.
                for fit in result.hide { fit.isHidden = false }
                return 0
            }
            ProjectFitsService.refreshSnapshot(in: context)
        }
        // An agent that opened the inbox just before the rename appends to
        // the renamed file: lines after what was read go back to the inbox.
        var keep = result.unmatched
        for file in readingFiles {
            guard let data = try? Data(contentsOf: file), let read = readBytes[file], data.count > read else { continue }
            keep += parse(String(decoding: data.suffix(from: read), as: UTF8.self))
        }
        guard putBack(keep) else { return result.hide.count }
        for file in readingFiles { try? fm.removeItem(at: file) }
        return result.hide.count
    }

    /// Appends entries to the inbox (lines for repos not under My Repos yet).
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
