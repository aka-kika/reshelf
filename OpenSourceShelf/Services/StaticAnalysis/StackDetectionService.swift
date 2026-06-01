import Foundation

struct StackDetection: Equatable, Hashable {
    var name: String
    var category: String
    var detectionSource: String
    var confidence: Double
    var evidencePath: String?
    var evidenceText: String?
}

enum StackDetectionService {
    static func detect(entries: [RepositoryInventoryEntry],
                       manifests: [ManifestDetection],
                       fileManager: FileManager = .default) -> [StackDetection] {
        var detections: [StackDetection] = []

        detections.append(contentsOf: detectLanguages(entries: entries))
        detections.append(contentsOf: detectFromManifests(manifests))
        detections.append(contentsOf: detectPackageManagers(from: manifests))
        detections.append(contentsOf: detectFromPackageJSON(manifests: manifests))
        detections.append(contentsOf: detectFromPythonRequirements(manifests: manifests))
        detections.append(contentsOf: detectFromFileStructure(entries: entries))
        detections.append(contentsOf: detectFromSourceText(entries: entries))

        let baseDetections = dedupe(detections)
        return dedupe(baseDetections + localFirstIndicators(from: baseDetections))
    }

    private static func detectLanguages(entries: [RepositoryInventoryEntry]) -> [StackDetection] {
        let extensionMap: [String: String] = [
            "swift": "Swift",
            "js": "JavaScript",
            "jsx": "JavaScript",
            "ts": "TypeScript",
            "tsx": "TypeScript",
            "py": "Python",
            "rs": "Rust",
            "go": "Go",
            "vue": "Vue",
            "svelte": "Svelte"
        ]

        var counts: [String: (count: Int, path: String)] = [:]
        for entry in entries where !entry.isDirectory {
            let ext = URL(fileURLWithPath: entry.relativePath).pathExtension.lowercased()
            guard let language = extensionMap[ext] else { continue }
            let current = counts[language] ?? (0, entry.relativePath)
            counts[language] = (current.count + 1, current.path)
        }

        return counts.map { language, value in
            StackDetection(name: language,
                           category: "language",
                           detectionSource: "file_extension",
                           confidence: value.count > 3 ? 0.8 : 0.6,
                           evidencePath: value.path,
                           evidenceText: "\(value.count) matching source file(s)")
        }
    }

    private static func detectFromManifests(_ manifests: [ManifestDetection]) -> [StackDetection] {
        manifests.compactMap { manifest in
            switch manifest.type {
            case "package_json", "pnpm_lock", "yarn_lock", "bun_lock", "turborepo", "nx_workspace":
                return StackDetection(name: "Node.js", category: "runtime", detectionSource: "manifest", confidence: 0.9, evidencePath: manifest.path, evidenceText: manifest.type)
            case "swift_package":
                return StackDetection(name: "Swift", category: "language", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "cargo_toml":
                return StackDetection(name: "Rust", category: "language", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "pyproject", "requirements":
                return StackDetection(name: "Python", category: "language", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "go_module":
                return StackDetection(name: "Go", category: "language", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "dockerfile", "docker_compose":
                return StackDetection(name: "Docker", category: "deployment", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "tauri_config":
                return StackDetection(name: "Tauri", category: "desktop", detectionSource: "manifest", confidence: 0.98, evidencePath: manifest.path, evidenceText: manifest.type)
            case "electron_builder":
                return StackDetection(name: "Electron", category: "desktop", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "wrangler":
                return StackDetection(name: "Cloudflare Workers", category: "deployment", detectionSource: "manifest", confidence: 0.95, evidencePath: manifest.path, evidenceText: manifest.type)
            case "mcp_config", "claude_desktop_config":
                return StackDetection(name: "MCP", category: "ai_integration", detectionSource: "manifest", confidence: 0.98, evidencePath: manifest.path, evidenceText: manifest.type)
            case "cursor_workspace":
                return StackDetection(name: "Cursor", category: "tooling", detectionSource: "file_structure", confidence: 0.9, evidencePath: manifest.path, evidenceText: manifest.type)
            default:
                return nil
            }
        }
    }

    private static func detectPackageManagers(from manifests: [ManifestDetection]) -> [StackDetection] {
        manifests.compactMap { manifest in
            let name: String
            switch manifest.type {
            case "package_json":
                name = "npm"
            case "pnpm_lock":
                name = "pnpm"
            case "yarn_lock":
                name = "Yarn"
            case "bun_lock":
                name = "Bun"
            case "swift_package":
                name = "Swift Package Manager"
            case "cargo_toml":
                name = "Cargo"
            case "pyproject":
                name = "Python packaging"
            case "requirements":
                name = "pip"
            case "go_module":
                name = "Go modules"
            default:
                return nil
            }

            return StackDetection(name: name,
                                  category: "package_manager",
                                  detectionSource: "manifest",
                                  confidence: 0.95,
                                  evidencePath: manifest.path,
                                  evidenceText: manifest.type)
        }
    }

    private static func detectFromPackageJSON(manifests: [ManifestDetection]) -> [StackDetection] {
        manifests
            .filter { $0.type == "package_json" }
            .flatMap { manifest -> [StackDetection] in
                let dependencies = packageDependencyNames(from: manifest.evidenceText)
                let mappings: [(names: [String], display: String, category: String)] = [
                    (["react", "react-dom"], "React", "framework"),
                    (["next"], "Next.js", "framework"),
                    (["vue"], "Vue", "framework"),
                    (["svelte", "@sveltejs/kit"], "Svelte", "framework"),
                    (["electron"], "Electron", "desktop"),
                    (["@tauri-apps/api", "@tauri-apps/cli"], "Tauri", "desktop"),
                    (["sqlite3", "better-sqlite3", "@libsql/client"], "SQLite", "database"),
                    (["pg", "postgres", "postgresql"], "Postgres", "database"),
                    (["@supabase/supabase-js", "@supabase/ssr"], "Supabase", "database"),
                    (["ollama"], "Ollama", "ai_integration"),
                    (["@modelcontextprotocol/sdk"], "MCP", "ai_integration"),
                    (["langchain"], "LangChain", "ai_integration"),
                    (["@langchain/langgraph", "langgraph"], "LangGraph", "ai_integration"),
                    (["openai"], "OpenAI SDK", "ai_integration"),
                    (["@anthropic-ai/sdk"], "Anthropic SDK", "ai_integration")
                ]

                return mappings.compactMap { mapping in
                    guard let dependency = mapping.names.first(where: { dependencies.contains($0) }) else {
                        return nil
                    }
                    return StackDetection(name: mapping.display,
                                          category: mapping.category,
                                          detectionSource: "dependency",
                                          confidence: 0.95,
                                          evidencePath: manifest.path,
                                          evidenceText: dependency)
                }
            }
    }

    private static func detectFromPythonRequirements(manifests: [ManifestDetection]) -> [StackDetection] {
        manifests
            .filter { $0.type == "requirements" || $0.type == "pyproject" }
            .flatMap { manifest -> [StackDetection] in
                let text = manifest.evidenceText?.lowercased() ?? ""
                let mappings: [(needle: String, name: String)] = [
                    ("langchain", "LangChain"),
                    ("langgraph", "LangGraph"),
                    ("openai", "OpenAI SDK"),
                    ("anthropic", "Anthropic SDK"),
                    ("ollama", "Ollama"),
                    ("modelcontextprotocol", "MCP"),
                    ("supabase", "Supabase"),
                    ("psycopg", "Postgres"),
                    ("sqlite", "SQLite")
                ]

                return mappings.compactMap { mapping in
                    guard text.contains(mapping.needle) else { return nil }
                    let category = ["Supabase", "Postgres", "SQLite"].contains(mapping.name) ? "database" : "ai_integration"
                    return StackDetection(name: mapping.name,
                                          category: category,
                                          detectionSource: "dependency",
                                          confidence: 0.85,
                                          evidencePath: manifest.path,
                                          evidenceText: mapping.needle)
                }
            }
    }

    private static func detectFromFileStructure(entries: [RepositoryInventoryEntry]) -> [StackDetection] {
        var detections: [StackDetection] = []
        let paths = Set(entries.map(\.relativePath))

        if paths.contains("next.config.js") || paths.contains("next.config.mjs") || paths.contains("next.config.ts") {
            detections.append(StackDetection(name: "Next.js", category: "framework", detectionSource: "config_file", confidence: 0.9, evidencePath: "next.config", evidenceText: "Next config file"))
        }
        if paths.contains("vite.config.js") || paths.contains("vite.config.ts") {
            detections.append(StackDetection(name: "Vite", category: "tooling", detectionSource: "config_file", confidence: 0.8, evidencePath: "vite.config", evidenceText: "Vite config file"))
        }
        if paths.contains("supabase/config.toml") {
            detections.append(StackDetection(name: "Supabase", category: "database", detectionSource: "config_file", confidence: 0.95, evidencePath: "supabase/config.toml", evidenceText: "Supabase config"))
        }

        return detections
    }

    private static func detectFromSourceText(entries: [RepositoryInventoryEntry]) -> [StackDetection] {
        var detections: [StackDetection] = []
        let sourceEntries = entries
            .filter { !$0.isDirectory && $0.sizeBytes ?? 0 <= 128_000 }
            .filter { ["swift", "js", "jsx", "ts", "tsx", "py", "rs", "go"].contains(URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased()) }
            .prefix(400)

        for entry in sourceEntries {
            guard let text = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            let lowercased = text.lowercased()

            if text.contains("import SwiftUI") {
                detections.append(StackDetection(name: "SwiftUI", category: "desktop", detectionSource: "source_import", confidence: 0.9, evidencePath: entry.relativePath, evidenceText: "import SwiftUI"))
            }
            if lowercased.contains("postgres") || lowercased.contains("postgresql") {
                detections.append(StackDetection(name: "Postgres", category: "database", detectionSource: "source_text", confidence: 0.55, evidencePath: entry.relativePath, evidenceText: "postgres"))
            }
            if lowercased.contains("sqlite") {
                detections.append(StackDetection(name: "SQLite", category: "database", detectionSource: "source_text", confidence: 0.6, evidencePath: entry.relativePath, evidenceText: "sqlite"))
            }
            if lowercased.contains("modelcontextprotocol") || lowercased.contains("mcp") {
                detections.append(StackDetection(name: "MCP", category: "ai_integration", detectionSource: "source_text", confidence: 0.55, evidencePath: entry.relativePath, evidenceText: "mcp"))
            }
        }

        return detections
    }

    private static func packageDependencyNames(from text: String?) -> Set<String> {
        guard let text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let dependencyKeys = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]
        return dependencyKeys.reduce(into: Set<String>()) { result, key in
            guard let dependencies = json[key] as? [String: Any] else { return }
            result.formUnion(dependencies.keys)
        }
    }

    private static func dedupe(_ detections: [StackDetection]) -> [StackDetection] {
        let grouped = Dictionary(grouping: detections) { "\($0.category)|\($0.name)" }
        return grouped.values.compactMap { group in
            group.sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return (lhs.evidencePath ?? "") < (rhs.evidencePath ?? "")
                }
                return lhs.confidence > rhs.confidence
            }.first
        }
        .sorted { lhs, rhs in
            if lhs.category == rhs.category {
                return lhs.name < rhs.name
            }
            return lhs.category < rhs.category
        }
    }

    private static func localFirstIndicators(from detections: [StackDetection]) -> [StackDetection] {
        var indicators: [StackDetection] = []
        let names = Set(detections.map(\.name))

        if names.contains("SQLite") {
            indicators.append(StackDetection(name: "Local data",
                                             category: "local_first",
                                             detectionSource: "stack_signal",
                                             confidence: 0.75,
                                             evidencePath: detections.first { $0.name == "SQLite" }?.evidencePath,
                                             evidenceText: "SQLite detected"))
        }

        if names.contains("Ollama") {
            indicators.append(StackDetection(name: "Local AI runtime",
                                             category: "local_first",
                                             detectionSource: "stack_signal",
                                             confidence: 0.75,
                                             evidencePath: detections.first { $0.name == "Ollama" }?.evidencePath,
                                             evidenceText: "Ollama detected"))
        }

        if names.contains("Docker") {
            indicators.append(StackDetection(name: "Self-hostable runtime",
                                             category: "local_first",
                                             detectionSource: "stack_signal",
                                             confidence: 0.65,
                                             evidencePath: detections.first { $0.name == "Docker" }?.evidencePath,
                                             evidenceText: "Docker detected"))
        }

        return indicators
    }
}
