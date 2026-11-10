import Foundation
import SwiftData

// Stand-in for the GitHub info refresh that CatalogCloneService.pull calls
// after a pull. The real one pulls in the GitHub API client; these tests never
// pull, so an empty result is enough to compile.
@MainActor
enum RepoInfoRefreshService {
    struct Result {}
    static func refresh(_ projects: [ToolProject], context: ModelContext) async -> Result { Result() }
}
