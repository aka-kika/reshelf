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

        guard let ownerRepo = GitHubRepositoryURL.ownerAndRepo(from: project.githubURL),
              let avatarURL = URL(string: "https://github.com/\(ownerRepo.owner).png?size=64") else {
            clearInFlight(project.id)
            return
        }

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
                // Re-fetch by id instead of touching the captured model: the
                // project can be deleted while the download is in flight (bulk
                // import + Remove Duplicate Repos is the common case), and
                // reading or writing a deleted PersistentModel is a fatal error.
                var descriptor = FetchDescriptor<ToolProject>(
                    predicate: #Predicate { $0.id == projectID }
                )
                descriptor.fetchLimit = 1
                guard let live = try? context.fetch(descriptor).first,
                      live.iconData == nil else { return }
                live.iconData = resized
                CatalogSave.save(context)
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
