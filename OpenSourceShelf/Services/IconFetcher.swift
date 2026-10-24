import Foundation
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

        // The avatar belongs to the owner. One that failed recently is left alone,
        // so a relaunch or a bulk import does not ask again for every repo.
        let owner = ownerRepo.owner
        let failures = IconFailureLog()
        guard failures.shouldTry(owner: owner) else {
            clearInFlight(project.id)
            return
        }

        let projectID = project.id

        URLSession.shared.dataTask(with: avatarURL) { data, response, error in
            defer { clearInFlight(projectID) }
            // No answer at all (offline, timeout) is not remembered: the next launch may work.
            guard error == nil, let httpResponse = response as? HTTPURLResponse else { return }
            guard httpResponse.statusCode == 200,
                  let data = data,
                  let resized = IconRules.resizedPNG(data, maxSide: 64) else {
                failures.recordFailure(owner: owner)
                return
            }
            failures.clear(owner: owner)

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
}
