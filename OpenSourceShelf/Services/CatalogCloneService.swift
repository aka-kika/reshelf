import Foundation
import AppKit

/// Resolves the root folder where repositories are cloned. The user can override
/// it in Settings; otherwise it defaults to `~/reshelf/repos`. Stored as a
/// plain path in UserDefaults (the app is not sandboxed, so no security-scoped
/// bookmark is needed). Existing clones are unaffected — only new clones use the
/// current value.
enum CloneLocation {
    static let storageKey = "reshelf.cloneRootPath"

    static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("reshelf", isDirectory: true)
            .appendingPathComponent("repos", isDirectory: true)
    }

    /// `true` when the user has chosen a custom folder (a non-empty stored path).
    static var isCustom: Bool {
        guard let stored = UserDefaults.standard.string(forKey: storageKey) else { return false }
        return !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var rootURL: URL {
        if let stored = UserDefaults.standard.string(forKey: storageKey) {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed, isDirectory: true)
            }
        }
        return defaultRootURL
    }
}

/// Standalone, AI-free repo cloning for the catalog. Clones a repo into the
/// clone folder, one subfolder per category, and helps open it — no intelligence
/// pipeline, no analysis, no git-lfs requirement (LFS filters are bypassed in
/// GitClient so LFS repos still clone).
enum CatalogCloneService {

    enum CloneError: LocalizedError {
        case invalidURL
        case folderInUse(String)
        case alreadyCloning

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "This project doesn't have a valid GitHub URL to clone."
            case let .folderInUse(path):
                return "A non-git folder already exists at \(path)."
            case .alreadyCloning:
                return "This repo is already being cloned."
            }
        }
    }

    /// `owner/repo` (lowercased) of clones running right now. Main actor only.
    @MainActor private static var clonesInProgress: Set<String> = []

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

    private static func cloneIndex() -> [String: URL] {
        cloneIndexLock.lock()
        defer { cloneIndexLock.unlock() }
        if let cached = cloneIndexCache { return cached }
        let index = scanCloneIndex(root: CloneLocation.rootURL)
        cloneIndexCache = index
        return index
    }

    /// `owner/repo` → clone folder for every finished checkout at reshelf's own
    /// layout, `<root>/<Category>/<repo>` or `<root>/<Category>/<owner>-<repo>`,
    /// where the folder name matches the checkout's own origin. Anything else
    /// under the root is not ours: with the clone folder pointed at a dev
    /// folder, a working copy at `<root>/<project>` or `<root>/work/<other name>`
    /// must not count as a clone (Remove Local Clone would trash it, Pull would
    /// reset it). Half-written clones are skipped too (`isFinishedCheckout`).
    static func scanCloneIndex(root: URL) -> [String: URL] {
        var index: [String: URL] = [:]
        let fm = FileManager.default
        guard let categoryDirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return index }
        for dir in categoryDirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for entry in entries {
                guard fm.fileExists(atPath: entry.appendingPathComponent(".git").path),
                      let slug = originSlug(fromConfigAt: entry),
                      isLayoutFolderName(entry.lastPathComponent, forSlug: slug),
                      isFinishedCheckout(entry) else { continue }
                if index[slug] == nil { index[slug] = entry }
            }
        }
        return index
    }

    /// Whether `folderName` is a name reshelf gives a clone of `slug`
    /// (`owner/repo`, lowercased): `<repo>` or the `<owner>-<repo>` fallback.
    static func isLayoutFolderName(_ folderName: String, forSlug slug: String) -> Bool {
        let parts = slug.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let name = folderName.lowercased()
        return name == parts[1] || name == "\(parts[0])-\(parts[1])"
    }

    /// A finished checkout: HEAD points at a commit and git wrote the index
    /// (the last step of a clone). A clone killed midway (app quit, crash,
    /// power cut) leaves `.git` with origin set but no HEAD branch, or no
    /// index if it died during checkout. File reads only — no git process —
    /// because the clone index runs this for every clone on the main thread.
    static func isFinishedCheckout(_ dir: URL) -> Bool {
        let gitDir = dir.appendingPathComponent(".git", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: gitDir.appendingPathComponent("index").path),
              let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
        else { return false }
        let target = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.hasPrefix("ref:") else {
            // Detached HEAD: a commit id.
            return target.count >= 40 && target.allSatisfy(\.isHexDigit)
        }
        // reftable repos keep refs in binary tables; the index file is the
        // evidence there.
        if fm.fileExists(atPath: gitDir.appendingPathComponent("reftable").path) { return true }
        let ref = target.dropFirst(4).trimmingCharacters(in: .whitespaces)
        guard ref.hasPrefix("refs/") else { return false }
        if let loose = try? String(contentsOf: gitDir.appendingPathComponent(ref), encoding: .utf8),
           !loose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let packed = try? String(contentsOf: gitDir.appendingPathComponent("packed-refs"), encoding: .utf8)
        else { return false }
        return packed.split(whereSeparator: \.isNewline).contains { $0.hasSuffix(" \(ref)") }
    }

    /// Extract `owner/repo` (lowercased) from a checkout's `.git/config` origin URL,
    /// handling https and ssh forms (`github.com/owner/repo[.git]`, `github.com:owner/repo`).
    static func originSlug(fromConfigAt dir: URL) -> String? {
        guard let config = try? String(contentsOf: dir.appendingPathComponent(".git/config"), encoding: .utf8),
              let hostRange = config.range(of: "github.com", options: .caseInsensitive) else { return nil }
        var rest = config[hostRange.upperBound...]
        guard let sep = rest.first, sep == ":" || sep == "/" else { return nil }
        rest = rest.dropFirst()
        let path = rest.prefix { !$0.isWhitespace }
        guard let (owner, repo) = GitHubRepositoryURL.ownerAndRepo(from: "github.com/\(path)") else { return nil }
        return "\(owner)/\(repo)".lowercased()
    }

    /// Sanitized, human-readable folder name for a project's category, so clones
    /// are grouped by category (`<repos>/<Category>/<repo>`) — e.g. point an AI
    /// agent at just the "Note Taking" folder. "AI / Agent" → "AI Agent"; blank
    /// → "Uncategorized".
    static func categoryFolderName(for project: ToolProject) -> String {
        folderName(forCategory: project.category)
    }

    static func folderName(forCategory category: String) -> String {
        let cleaned = category
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline })
            .joined(separator: " ")
        // "." or ".." would put clones in the root or above it.
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "Uncategorized" : cleaned
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
        // Exact slug comparison, not substring: `contains("kika/tool")` also
        // matched a clone of "akika/tool", silently adopting a different repo's
        // checkout as this one's clone.
        originSlug(fromConfigAt: dir) == "\(owner)/\(repo)".lowercased()
    }

    /// The existing clone for a project, if one is present. O(1) lookup in the
    /// cached clone index — finds the clone regardless of which category folder it
    /// sits in (even after the repo is recategorized), and stays fast when called
    /// per row during list rendering.
    static func existingClone(for project: ToolProject) -> URL? {
        guard let (owner, repo) = GitHubRepositoryURL.ownerAndRepo(from: project.githubURL) else { return nil }
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
        guard let (owner, repo) = GitHubRepositoryURL.ownerAndRepo(from: project.githubURL) else { return nil }
        let candidates = candidatePaths(owner: owner, repo: repo, category: categoryFolderName(for: project))
        for path in candidates {
            // A candidate that already holds THIS repo's checkout (index missed
            // it — e.g. restored from Trash or cloned outside the app) IS the
            // destination; anything else occupying it means try the next name.
            if originMatches(path, owner: owner, repo: repo) { return path }
            if !FileManager.default.fileExists(atPath: path.path) { return path }
        }
        return candidates.last
    }

    /// One-time tidy: move legacy flat clones (sitting directly in the clone root)
    /// into their project's category subfolder. No-op once everything is organized.
    @discardableResult
    static func migrateClonesIntoCategoryFolders(_ projects: [ToolProject]) -> Int {
        // Flat clones only ever existed in the default folder. A custom clone
        // folder may be a dev folder, whose own checkouts must never be moved.
        guard !CloneLocation.isCustom else { return 0 }
        let fm = FileManager.default
        let root = CloneLocation.rootURL
        var moved = 0
        for project in projects {
            guard let (owner, repo) = GitHubRepositoryURL.ownerAndRepo(from: project.githubURL) else { continue }
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

    /// One-time move for merged categories: every clone in an old category
    /// folder goes into the merged one (`<root>/Coding Agents/x` →
    /// `<root>/AI Agent/x`). A name already taken in the target stays where it
    /// is — clone lookup scans every category folder, so it is still found. An
    /// old folder left with nothing but .DS_Store is tidied away.
    @discardableResult
    static func mergeCategoryFolders(_ merges: [String: String]) -> Int {
        let fm = FileManager.default
        let root = CloneLocation.rootURL
        var moved = 0
        for (oldCategory, newCategory) in merges {
            let oldDir = root.appendingPathComponent(folderName(forCategory: oldCategory), isDirectory: true)
            let newDir = root.appendingPathComponent(folderName(forCategory: newCategory), isDirectory: true)
            guard oldDir.path != newDir.path,
                  let entries = try? fm.contentsOfDirectory(atPath: oldDir.path) else { continue }
            for entry in entries where entry != ".DS_Store" {
                let dest = newDir.appendingPathComponent(entry, isDirectory: true)
                guard !fm.fileExists(atPath: dest.path) else { continue }
                do {
                    try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
                    try fm.moveItem(at: oldDir.appendingPathComponent(entry, isDirectory: true), to: dest)
                    moved += 1
                } catch { /* leave in place on failure */ }
            }
            if let leftovers = try? fm.contentsOfDirectory(atPath: oldDir.path),
               leftovers.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: oldDir)
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
    ///
    /// @MainActor (like `updateStatus`/`pull` below): these take a SwiftData
    /// @Model bound to the main context, and a nonisolated async func hops to
    /// the cooperative pool (SE-0338), racing its model reads against
    /// main-actor writes. Git itself still runs off-main inside GitClient.
    @MainActor
    static func clone(_ project: ToolProject) async throws -> URL {
        if let existing = existingClone(for: project) { return existing }
        // The index only self-heals stale HITS (folder deleted behind its back),
        // not stale MISSES (clone appeared behind its back). Before concluding a
        // network clone is needed, rescan once — otherwise a repo that's already
        // on disk shows un-cloned, and cloning it again errors or duplicates.
        invalidateCloneIndex()
        if let existing = existingClone(for: project) { return existing }
        guard let (owner, repo) = GitHubRepositoryURL.ownerAndRepo(from: project.githubURL),
              let dest = destination(for: project) else {
            throw CloneError.invalidURL
        }
        let fm = FileManager.default
        // The list and the inspector each have a Clone button: a second clone of
        // the same repo while the first runs would see the first one's
        // half-written folder below and trash it.
        let slug = "\(owner)/\(repo)".lowercased()
        guard !clonesInProgress.contains(slug) else { throw CloneError.alreadyCloning }
        clonesInProgress.insert(slug)
        defer { clonesInProgress.remove(slug) }

        if fm.fileExists(atPath: dest.path) {
            if originMatches(dest, owner: owner, repo: repo) {
                // Adopt a finished checkout of this exact repo that the index
                // missed rather than failing on it.
                if isFinishedCheckout(dest), await GitClient().headResolves(repositoryURL: dest) {
                    invalidateCloneIndex()
                    AppRefreshBus.emit(.catalogStateUpdated)
                    return dest
                }
                // A clone of this repo that died midway: origin is set but the
                // checkout never finished. Trash it (recoverable) and clone again.
                try fm.trashItem(at: dest, resultingItemURL: nil)
            }
        }

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
        // Clones live on disk, not in SwiftData, so no @Query sees this one:
        // the sidebar's Cloned count and the row badges wait for this event.
        AppRefreshBus.emit(.catalogStateUpdated)
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
        AppRefreshBus.emit(.catalogStateUpdated)
    }

    // MARK: - Updates (plain git — no AI)

    enum UpdateStatus: Equatable {
        case upToDate
        case updatesAvailable
        case error(String)
    }

    /// Compares the local clone's commit to the remote default branch's tip via a
    /// cheap `ls-remote` (no fetch). Different SHA → upstream has updates.
    @MainActor
    static func updateStatus(for project: ToolProject) async -> UpdateStatus {
        guard let dir = existingClone(for: project) else { return .error("Not cloned.") }
        let git = GitClient()
        do {
            async let localTask = git.currentHead(repositoryURL: dir)
            async let remoteTask = git.remoteDefaultHead(repositoryURL: dir)
            let (local, remote) = try await (localTask, remoteTask)
            guard let local, let remote else { return .error("Couldn't read commits.") }
            if local == remote { return .upToDate }
            // A clone with its own commits on top of upstream's tip is not behind.
            return await git.headContains(remote, repositoryURL: dir) ? .upToDate : .updatesAvailable
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Sync the clone to its upstream default branch (LFS-bypassed, like clone).
    /// Fast-forwards when possible; resets to upstream when the clone has diverged
    /// (e.g. the project force-pushed/rebased its default branch) so updates don't
    /// get stuck. Throws `GitClientError.localChangesPresent` — leaving the clone
    /// untouched — if the working tree has local edits or the clone has commits
    /// of its own that upstream never had. After a successful pull
    /// the repo's GitHub info (stars, license, last activity) is refreshed too:
    /// cloned repos are skipped by Refresh Repo Info, so this is their refresh.
    @MainActor
    static func pull(_ project: ToolProject) async throws {
        guard let dir = existingClone(for: project) else { throw CloneError.invalidURL }
        // The row can be deleted during the git work: keep only plain values.
        let projectID = project.id
        let context = project.modelContext
        try await GitClient().syncToUpstream(repositoryURL: dir)
        if let context, let live = LiveProject.fetch(projectID, in: context) {
            _ = await RepoInfoRefreshService.refresh([live], context: context)
        }
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
