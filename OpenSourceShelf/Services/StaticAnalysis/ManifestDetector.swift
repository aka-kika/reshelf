import Foundation

struct RepositoryInventoryEntry: Equatable {
    var relativePath: String
    var url: URL
    var isDirectory: Bool
    var sizeBytes: Int64?
    var depth: Int
}

struct ManifestDetection: Equatable {
    var path: String
    var type: String
    var ecosystem: String
    var evidenceText: String?
}

enum ManifestDetector {
    static func detect(in entries: [RepositoryInventoryEntry],
                       rootURL: URL,
                       fileManager: FileManager = .default) -> [ManifestDetection] {
        var detections: [ManifestDetection] = []

        if fileManager.fileExists(atPath: rootURL.appendingPathComponent(".cursor", isDirectory: true).path) {
            detections.append(ManifestDetection(path: ".cursor",
                                                type: "cursor_workspace",
                                                ecosystem: "Cursor",
                                                evidenceText: ".cursor directory"))
        }

        for entry in entries where !entry.isDirectory {
            guard let definition = definition(for: entry.relativePath) else { continue }
            detections.append(
                ManifestDetection(path: entry.relativePath,
                                  type: definition.type,
                                  ecosystem: definition.ecosystem,
                                  evidenceText: evidenceSnippet(at: entry.url))
            )
        }

        return uniqueDetections(detections)
    }

    private static func definition(for path: String) -> (type: String, ecosystem: String)? {
        let fileName = URL(fileURLWithPath: path).lastPathComponent

        switch fileName {
        case "package.json":
            return ("package_json", "JavaScript")
        case "pnpm-lock.yaml":
            return ("pnpm_lock", "JavaScript")
        case "yarn.lock":
            return ("yarn_lock", "JavaScript")
        case "bun.lockb":
            return ("bun_lock", "JavaScript")
        case "Package.swift":
            return ("swift_package", "Swift")
        case "Cargo.toml":
            return ("cargo_toml", "Rust")
        case "pyproject.toml":
            return ("pyproject", "Python")
        case "requirements.txt":
            return ("requirements", "Python")
        case "go.mod":
            return ("go_module", "Go")
        case "Dockerfile":
            return ("dockerfile", "Docker")
        case "docker-compose.yml", "compose.yaml":
            return ("docker_compose", "Docker")
        case "tauri.conf.json":
            return ("tauri_config", "Tauri")
        case "electron-builder.yml":
            return ("electron_builder", "Electron")
        case "wrangler.toml":
            return ("wrangler", "Cloudflare")
        case "turbo.json":
            return ("turborepo", "JavaScript")
        case "nx.json":
            return ("nx_workspace", "JavaScript")
        case "mcp.json":
            return ("mcp_config", "MCP")
        case "claude_desktop_config.json":
            return ("claude_desktop_config", "MCP")
        default:
            return nil
        }
    }

    private static func evidenceSnippet(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }

        let prefix = data.prefix(8_192)
        guard let text = String(data: prefix, encoding: .utf8) else {
            return URL(fileURLWithPath: url.path).lastPathComponent
        }

        return String(text.prefix(1_000))
    }

    private static func uniqueDetections(_ detections: [ManifestDetection]) -> [ManifestDetection] {
        var seen: Set<String> = []
        return detections.filter { detection in
            let key = "\(detection.path)|\(detection.type)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
