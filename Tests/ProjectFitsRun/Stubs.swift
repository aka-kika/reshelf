import Foundation
import SwiftData

// A fake GitHub for the Find Fits run: the real QuickCaptureService pulls in
// the whole capture path, and these tests must never touch the network.
// `FakeGitHub.pages` maps a URL path (with query) to a reply.
enum FakeGitHub {
    enum Reply {
        case body(String)
        case notFound
        case rateLimited
    }
    nonisolated(unsafe) static var pages: [String: Reply] = [:]
    nonisolated(unsafe) static var requested: [String] = []
}

enum CaptureError: LocalizedError {
    case invalidURL
    case notFound(String)
    case unauthorized
    case forbidden(String)
    case rateLimited(resetText: String?)
    case httpError(Int)
    case decodingFailed
    case network(String)

    var errorDescription: String? { "\(self)" }
}

enum QuickCaptureService {
    static func getJSON(from url: URL, context: String,
                        accept: String = "application/vnd.github.v3+json") async throws -> Data {
        var key = url.path
        if let query = url.query { key += "?" + query }
        FakeGitHub.requested.append(key)
        switch FakeGitHub.pages[key] {
        case .body(let text)?: return Data(text.utf8)
        case .rateLimited?: throw CaptureError.rateLimited(resetText: nil)
        case .notFound?, nil: throw CaptureError.notFound(context)
        }
    }
}

@MainActor
enum RepoInfoRefreshService {
    struct Result {}
    static func refresh(_ projects: [ToolProject], context: ModelContext) async -> Result { Result() }
}
