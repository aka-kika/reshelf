import Foundation
import AppKit

/// Standalone, AI-free repo cloning for the catalog. Clones a repo to the user's
/// Clones folder (organized by owner/name) and helps open it — no intelligence
/// pipeline, no analysis, no git-lfs requirement (LFS filters are bypassed in
/// GitClient so LFS repos still clone).
enum CatalogCloneService {

    enum CloneError: LocalizedError {
        case invalidURL
        case folderInUse(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "This project doesn't have a valid GitHub URL to clone."
            case let .folderInUse(path):
                return "A non-git folder already exists at \(path)."
            }
        }
    }

    // MARK: - Clone index (cached)

    /// Cached map of `owner/repo` (lowercased) → clone folder. Built by one scan of
    /// the clone tree; lookups are O(1). `isCloned`/`existingClone` are called per
    /// row on every list re-render, so scanning the filesystem each time made
    /// clicking sluggish — this cache fixes that. Invalidated on clone/migrate.
    private static var cloneIndexCache: [String: URL]?
    private static let cloneIndexLock = NSLock()

    /// Drop the cached clone index so the next lookup rescans (after a new clone,
    /// a migration, or any change to what's on disk).
    static func invalidateCloneIndex() {
        cloneIndexLock.lock()
        cloneIndexCache = nil
        cloneIndexLock.unlock()
    }

    /// `owner/repo` → clone folder for every git checkout under the clone root
    /// (root level for legacy flat clones, plus one level deep for category
    /// folders). One filesystem walk, then cached.
    private static func cloneIndex() -> [String: URL] {
        cloneIndexLock.lock()
        defer { cloneIndexLock.unlock() }
        if let cached = cloneIndexCache { return cached }

        var index: [String: URL] = [:]
        let fm = FileManager.default
        let root = CloneLocation.rootURL

        var dirs: [URL] = [root]
        if let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                dirs.append(entry)
            }
        }

        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                guard fm.fileExists(atPath: entry.appendingPathComponent(".git").path),
                      let slug = originSlug(fromConfigAt: entry) else { continue }
                if index[slug] == nil { index[slug] = entry }
            }
        }

        cloneIndexCache = index
        return index
    }

    /// Extract `owner/repo` (lowercased) from a checkout's `.git/config` origin URL,
    /// handling https and ssh forms (`github.com/owner/repo[.git]`, `github.com:owner/repo`).
    private static func originSlug(fromConfigAt dir: URL) -> String? {
        guard let config = try? String(contentsOf: dir.appendingPathComponent(".git/config"), encoding: .utf8),
              let hostRange = config.range(of: "github.com", options: .caseInsensitive) else { return nil }
        var rest = config[hostRange.upperBound...]
        guard let sep = rest.first, sep == ":" || sep == "/" else { return nil }
        rest = rest.dropFirst()
        let token = rest.prefix { !$0.isWhitespace }
        let parts = token.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        var repo = String(parts[1])
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        return "\(parts[0])/\(repo)".lowercased()
    }

    /// Sanitized, human-readable folder name for a project's category, so clones
    /// are grouped by category (`<repos>/<Category>/<repo>`) — e.g. point an AI
    /// agent at just the "Note Taking" folder. "AI / Agent" → "AI Agent"; blank
    /// → "Uncategorized".
    static func categoryFolderName(for project: ToolProject) -> String {
        let cleaned = project.category
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline })
            .joined(separator: " ")
        return cleaned.isEmpty ? "Uncategorized" : cleaned
    }

    /// Where a NEW clone should go: under the project's category subfolder, the
    /// flat repo name first (clean), then `<owner>-<repo>` as a collision fallback.
    private static func candidatePaths(owner: String, repo: String, category: String) -> [URL] {
        let dir = CloneLocation.rootURL.appendingPathComponent(category, isDirectory: true)
        return [
            dir.appendingPathComponent(repo, isDirectory: true),
            dir.appendingPathComponent("\(owner)-\(repo)", isDirectory: true),
        ]
    }

    /// Whether the git clone at `dir` is actually this owner/repo (so a same-named
    /// folder for a *different* repo doesn't get mistaken for it).
    private static func originMatches(_ dir: URL, owner: String, repo: String) -> Bool {
        guard let config = try? String(contentsOf: dir.appendingPathComponent(".git/config"), encoding: .utf8) else {
            return false
        }
        return config.lowercased().contains("\(owner)/\(repo)".lowercased())
    }

    /// The existing clone for a project, if one is present. O(1) lookup in the
    /// cached clone index — finds the clone regardless of which category folder it
    /// sits in (even after the repo is recategorized), and stays fast when called
    /// per row during list rendering.
    static func existingClone(for project: ToolProject) -> URL? {
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else { return nil }
        guard let cached = cloneIndex()["\(owner)/\(repo)".lowercased()] else { return nil }
        // Self-heal: if the user deleted the folder in Finder, the cached entry is
        // stale — drop the index and rescan once so the Cloned badge clears without
        // an app restart. (One cheap stat per hit; the rescan only happens when a
        // stale entry is actually found.)
        guard FileManager.default.fileExists(atPath: cached.appendingPathComponent(".git").path) else {
            invalidateCloneIndex()
            return cloneIndex()["\(owner)/\(repo)".lowercased()]
        }
        return cached
    }

    /// Where a project is/would be cloned: the existing clone, else the first free
    /// candidate under its category subfolder (`<category>/<repo>`, then
    /// `<category>/<owner>-<repo>`).
    static func destination(for project: ToolProject) -> URL? {
        if let existing = existingClone(for: project) { return existing }
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else { return nil }
        let candidates = candidatePaths(owner: owner, repo: repo, category: categoryFolderName(for: project))
        for path in candidates where !FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return candidates.last
    }

    /// One-time tidy: move legacy flat clones (sitting directly in the clone root)
    /// into their project's category subfolder. No-op once everything is organized.
    @discardableResult
    static func migrateClonesIntoCategoryFolders(_ projects: [ToolProject]) -> Int {
        let fm = FileManager.default
        let root = CloneLocation.rootURL
        var moved = 0
        for project in projects {
            guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else { continue }
            for name in [repo, "\(owner)-\(repo)"] {
                let flat = root.appendingPathComponent(name, isDirectory: true)
                guard fm.fileExists(atPath: flat.appendingPathComponent(".git").path),
                      originMatches(flat, owner: owner, repo: repo) else { continue }
                let categoryDir = root.appendingPathComponent(categoryFolderName(for: project), isDirectory: true)
                let dest = categoryDir.appendingPathComponent(name, isDirectory: true)
                guard flat.path != dest.path, !fm.fileExists(atPath: dest.path) else { continue }
                do {
                    try fm.createDirectory(at: categoryDir, withIntermediateDirectories: true)
                    try fm.moveItem(at: flat, to: dest)
                    moved += 1
                } catch { /* leave in place on failure */ }
                break
            }
        }
        if moved > 0 { invalidateCloneIndex() }
        return moved
    }

    static func isCloned(_ project: ToolProject) -> Bool {
        existingClone(for: project) != nil
    }

    /// Clones the project (full clone). Returns the local path; returns the existing
    /// path if already cloned. Clears an empty/failed leftover at the target first.
    static func clone(_ project: ToolProject) async throws -> URL {
        if let existing = existingClone(for: project) { return existing }
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL),
              let dest = destination(for: project) else {
            throw CloneError.invalidURL
        }
        let fm = FileManager.default

        if fm.fileExists(atPath: dest.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: dest.path)) ?? []
            if contents.isEmpty || contents.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: dest)
            } else {
                throw CloneError.folderInUse(dest.path)
            }
        }

        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let url = "https://github.com/\(owner)/\(repo)"
        try await GitClient().clone(repositoryURL: url, destinationURL: dest, blobless: false)
        invalidateCloneIndex()
        return dest
    }

    /// Remove a project's local clone. The folder is moved to the Trash (not
    /// deleted outright) so the user can recover it; an emptied category folder is
    /// tidied away too. The catalog entry itself is untouched.
    static func removeClone(_ project: ToolProject) throws {
        guard let dir = existingClone(for: project) else { return }
        let fm = FileManager.default
        try fm.trashItem(at: dir, resultingItemURL: nil)
        let parent = dir.deletingLastPathComponent()
        if parent.path != CloneLocation.rootURL.path,
           let leftovers = try? fm.contentsOfDirectory(atPath: parent.path),
           leftovers.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(at: parent)
        }
        invalidateCloneIndex()
    }

    // MARK: - Updates (plain git — no AI)

    enum UpdateStatus: Equatable {
        case upToDate
        case updatesAvailable
        case error(String)
    }

    /// Compares the local clone's commit to the remote default branch's tip via a
    /// cheap `ls-remote` (no fetch). Different SHA → upstream has updates.
    static func updateStatus(for project: ToolProject) async -> UpdateStatus {
        guard let dir = existingClone(for: project) else { return .error("Not cloned.") }
        let git = GitClient()
        do {
            async let localTask = git.currentHead(repositoryURL: dir)
            async let remoteTask = git.remoteDefaultHead(repositoryURL: dir)
            let (local, remote) = try await (localTask, remoteTask)
            guard let local, let remote else { return .error("Couldn't read commits.") }
            return local == remote ? .upToDate : .updatesAvailable
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Sync the clone to its upstream default branch (LFS-bypassed, like clone).
    /// Fast-forwards when possible; resets to upstream when the clone has diverged
    /// (e.g. the project force-pushed/rebased its default branch) so updates don't
    /// get stuck. Throws `GitClientError.localChangesPresent` — leaving the clone
    /// untouched — if the working tree has local edits.
    static func pull(_ project: ToolProject) async throws {
        guard let dir = existingClone(for: project) else { throw CloneError.invalidURL }
        try await GitClient().syncToUpstream(repositoryURL: dir)
    }

    // MARK: - Opening

    @MainActor
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    static func openInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([url], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// Code editors found in /Applications, for an "Open in…" menu.
    static func installedEditors() -> [(name: String, appURL: URL)] {
        let candidates: [(String, String)] = [
            ("Visual Studio Code", "/Applications/Visual Studio Code.app"),
            ("Cursor", "/Applications/Cursor.app"),
            ("Zed", "/Applications/Zed.app"),
            ("Sublime Text", "/Applications/Sublime Text.app"),
            ("Nova", "/Applications/Nova.app"),
            ("Xcode", "/Applications/Xcode.app"),
        ]
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.1) }
            .map { (name: $0.0, appURL: URL(fileURLWithPath: $0.1)) }
    }

    @MainActor
    static func open(_ url: URL, inEditorAt appURL: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }
}
