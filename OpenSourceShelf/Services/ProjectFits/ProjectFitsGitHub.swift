import Foundation

/// The GitHub calls Project fits makes: the list of Kika's own repos for the
/// Add popup, and one README at a time. Read-only, same token as everywhere
/// (`GitHubAuth`), same error messages as Quick Capture (`CaptureError`).
enum ProjectFitsGitHub {
    /// One of her repos in the Add popup.
    struct OwnRepo: Decodable, Identifiable, Equatable {
        let fullName: String
        let description: String?
        let htmlUrl: String
        let isPrivate: Bool
        let fork: Bool
        let archived: Bool
        let pushedAt: String?
        let topics: [String]?

        var id: String { fullName.lowercased() }
        var name: String { fullName.split(separator: "/").last.map(String.init) ?? fullName }

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case description
            case htmlUrl = "html_url"
            case isPrivate = "private"
            case fork, archived, topics
            case pushedAt = "pushed_at"
        }
    }

    /// At most this many pages of 100: enough for anyone's own repos, and a
    /// hard stop against paging forever.
    static let maxPages = 5

    /// Her own repos, newest push first, without forks and archived ones
    /// (Kika, 10 Nov: only repos she owns). With a token: every repo the
    /// token can see that she owns, private ones too. Without: the public
    /// repos of `user`.
    static func ownRepos(user: String?, useToken: Bool = GitHubAuth.hasToken) async throws -> [OwnRepo] {
        var all: [OwnRepo] = []
        for page in 1...maxPages {
            let path: String
            if useToken {
                path = "/user/repos?affiliation=owner&sort=pushed&per_page=100&page=\(page)"
            } else {
                let name = (user ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                      let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                else { throw CaptureError.invalidURL }
                path = "/users/\(encoded)/repos?type=owner&sort=pushed&per_page=100&page=\(page)"
            }
            guard let url = URL(string: "https://api.github.com" + path) else { throw CaptureError.invalidURL }
            let data = try await QuickCaptureService.getJSON(from: url, context: "your repos")
            let batch: [OwnRepo]
            do {
                batch = try JSONDecoder().decode([OwnRepo].self, from: data)
            } catch {
                throw CaptureError.decodingFailed
            }
            all += batch
            if batch.count < 100 { break }
        }
        return all.filter { !$0.fork && !$0.archived }
    }

    /// A repo's README as plain text, or nil when it has none. Other failures
    /// (rate limit, no network) throw, so a run can say why it used saved info.
    static func readme(fullName: String) async throws -> String? {
        guard let parsed = GitHubRepositoryURL.parseFullName(fullName),
              let url = URL(string: "https://api.github.com/repos/\(parsed.owner)/\(parsed.name)/readme")
        else { return nil }
        do {
            let data = try await QuickCaptureService.getJSON(from: url, context: fullName,
                                                             accept: "application/vnd.github.raw")
            return String(data: data, encoding: .utf8)
        } catch CaptureError.notFound {
            return nil
        }
    }

    /// The README of a local clone, when there is one on disk.
    static func readmeOnDisk(at folder: URL) -> String? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return nil }
        let pick = names.first { $0.lowercased() == "readme.md" }
            ?? names.first { $0.lowercased().hasPrefix("readme") }
        guard let pick else { return nil }
        let url = folder.appendingPathComponent(pick)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
