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

    /// Where a project would be cloned: `<Clones folder>/<owner>/<repo>`.
    static func destination(for project: ToolProject) -> URL? {
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else { return nil }
        return CloneLocation.rootURL
            .appendingPathComponent(owner, isDirectory: true)
            .appendingPathComponent(repo, isDirectory: true)
    }

    /// True when a valid git clone already exists at the destination.
    static func isCloned(_ project: ToolProject) -> Bool {
        guard let dest = destination(for: project) else { return false }
        return FileManager.default.fileExists(atPath: dest.appendingPathComponent(".git").path)
    }

    /// Clones the project (full clone). Returns the local path. If it's already
    /// cloned, returns the existing path. Removes a failed/partial leftover first.
    static func clone(_ project: ToolProject) async throws -> URL {
        guard let (owner, repo) = IconFetcher.extractOwnerRepo(from: project.githubURL) else {
            throw CloneError.invalidURL
        }
        let fm = FileManager.default
        let dest = CloneLocation.rootURL
            .appendingPathComponent(owner, isDirectory: true)
            .appendingPathComponent(repo, isDirectory: true)

        if fm.fileExists(atPath: dest.path) {
            if fm.fileExists(atPath: dest.appendingPathComponent(".git").path) {
                return dest // already cloned
            }
            // A leftover folder under our managed Clones dir without a .git — safe
            // to clear (only true when it's empty / a failed partial clone).
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
