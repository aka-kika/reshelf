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

    /// Candidate folder names for a repo: the flat repo name first (clean — you
    /// browse repo names directly), then `<owner>-<repo>` as a collision fallback.
    private static func candidatePaths(owner: String, repo: String) -> [URL] {
        let root = CloneLocation.rootURL
        return [
            root.appendingPathComponent(repo, isDirectory: true),
            root.appendingPathComponent("\(owner)-\(repo)", isDirectory: true),
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

    /// The existing clone for a project, if one is present.
    static func existingClone(for project: ToolProject) -> URL? {
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else { return nil }
        let fm = FileManager.default
        for path in candidatePaths(owner: owner, repo: repo)
        where fm.fileExists(atPath: path.appendingPathComponent(".git").path)
            && originMatches(path, owner: owner, repo: repo) {
            return path
        }
        return nil
    }

    /// Where a project is/would be cloned: the existing clone, else the first free
    /// candidate (`<repo>`, then `<owner>-<repo>`).
    static func destination(for project: ToolProject) -> URL? {
        if let existing = existingClone(for: project) { return existing }
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else { return nil }
        let candidates = candidatePaths(owner: owner, repo: repo)
        for path in candidates where !FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        return candidates.last
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
        return dest
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

    /// Fast-forward pull (LFS-bypassed, like clone).
    static func pull(_ project: ToolProject) async throws {
        guard let dir = existingClone(for: project) else { throw CloneError.invalidURL }
        try await GitClient().pullFastForward(repositoryURL: dir)
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
