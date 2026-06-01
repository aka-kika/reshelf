import Foundation
import AppKit
import SwiftData

enum IconFetcher {
    private static let inFlightLock = NSLock()
    private static var inFlightProjectIDs = Set<UUID>()

    /// Derives the avatar URL from a GitHub repo URL and downloads the icon into the model.
    static func fetch(for project: ToolProject, in context: ModelContext) {
        guard !project.githubURL.isEmpty else { return }
        guard project.iconData == nil else { return }

        inFlightLock.lock()
        let shouldStart = inFlightProjectIDs.insert(project.id).inserted
        inFlightLock.unlock()
        guard shouldStart else { return }

        guard let ownerRepo = extractOwnerRepo(from: project.githubURL) else {
            clearInFlight(project.id)
            return
        }

        let avatarURL = URL(string: "https://github.com/\(ownerRepo.owner).png?size=64")!
        let projectID = project.id

        URLSession.shared.dataTask(with: avatarURL) { data, response, _ in
            defer { clearInFlight(projectID) }
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  NSImage(data: data) != nil else {
                return
            }

            let resized = resizeIfNeeded(data, maxSize: 64) ?? data

            DispatchQueue.main.async {
                guard project.iconData == nil else { return }
                project.iconData = resized
                try? context.save()
            }
        }.resume()
    }

    private static func clearInFlight(_ projectID: UUID) {
        inFlightLock.lock()
        inFlightProjectIDs.remove(projectID)
        inFlightLock.unlock()
    }

    static func fetchAll(for projects: [ToolProject], in context: ModelContext) {
        for project in projects where project.iconData == nil {
            fetch(for: project, in: context)
        }
    }

    // MARK: - Helpers

    static func iconForProject(_ project: ToolProject) -> NSImage? {
        if let data = project.iconData {
            return NSImage(data: data)
        }
        return nil
    }

    static func extractOwnerRepo(from url: String) -> (owner: String, repo: String)? {
        let cleaned = url
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")

        guard cleaned.hasPrefix("github.com/") else { return nil }
        let parts = cleaned
            .replacingOccurrences(of: "github.com/", with: "")
            .split(separator: "/")
            .filter { !$0.isEmpty && $0 != "tree" && $0 != "blob" }

        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func resizeIfNeeded(_ data: Data, maxSize: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return data }
        let size = image.size
        guard size.width > maxSize || size.height > maxSize else { return data }

        let ratio = max(maxSize / size.width, maxSize / size.height)
        let newSize = NSSize(width: size.width * ratio, height: size.height * ratio)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: .zero, operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        return resized.tiffRepresentation(using: .lzw, factor: 1.0)
    }
}
