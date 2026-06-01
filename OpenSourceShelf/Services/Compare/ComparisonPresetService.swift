import Foundation

enum ComparisonPreset: String, CaseIterable, Identifiable {
    case localAIUIs = "Local AI UIs"
    case lowCodeBuilders = "Low-Code Builders"
    case macOSDesktopTools = "macOS Desktop Tools"
    case mcpTools = "MCP Tools"
    case databaseTools = "Database Tools"
    case agentTooling = "Agent Tooling"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .localAIUIs:
            return "Ollama, Open WebUI, LibreChat, Flowise-style local AI surfaces"
        case .lowCodeBuilders:
            return "ToolJet, Budibase, Appsmith-style builders"
        case .macOSDesktopTools:
            return "SwiftUI, Tauri, Electron desktop repos"
        case .mcpTools:
            return "Repos with MCP protocol or ecosystem signals"
        case .databaseTools:
            return "Directus, Payload, Supabase-style data tools"
        case .agentTooling:
            return "LangChain, agent, and Codex-adjacent tooling"
        }
    }
}

struct ComparisonPresetCandidate: Identifiable, Equatable {
    var id: String { repositoryID }
    var repositoryID: String
    var fullName: String
    var score: Double
    var reason: String
}

enum ComparisonPresetService {
    static func suggestCandidates(for preset: ComparisonPreset,
                                  limit: Int = 8,
                                  database: IntelligenceDatabase = .shared) throws -> [ComparisonPresetCandidate] {
        try database.initialize()
        let candidates = try database.fetchCompareFocusCandidates(limit: 500)
        var scored: [ComparisonPresetCandidate] = []

        for candidate in candidates {
            guard let repository = try database.fetchRepository(id: candidate.id) else { continue }
            let stack = try database.fetchDetectedStackItems(repositoryID: candidate.id).map(\.name)
            let stackLower = stack.map { $0.lowercased() }
            let metadata = try database.fetchMetadata(repositoryID: candidate.id)
            let topics = decodeTopics(metadata?.topicsJSON ?? "[]")
            let relationships = try database.fetchGraphRelationships(repositoryID: candidate.id)
            let ecosystems = try database.fetchEcosystemClusters(types: ["ecosystem", "workflow"])
                .filter { decodeStringArray($0.repositoryIDsJSON).contains(candidate.id) }
                .map(\.name)

            let evaluation = score(preset: preset,
                                   fullName: repository.fullName,
                                   stackLower: stackLower,
                                   topics: topics,
                                   ecosystems: ecosystems,
                                   relationships: relationships,
                                   relationshipCount: candidate.relationshipCount)

            if evaluation.score > 0 {
                scored.append(ComparisonPresetCandidate(
                    repositoryID: candidate.id,
                    fullName: repository.fullName,
                    score: evaluation.score,
                    reason: evaluation.reason
                ))
            }
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.fullName < rhs.fullName }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func score(preset: ComparisonPreset,
                              fullName: String,
                              stackLower: [String],
                              topics: [String],
                              ecosystems: [String],
                              relationships: [GraphRelationshipSummary],
                              relationshipCount: Int) -> (score: Double, reason: String) {
        let haystack = (stackLower + topics.map { $0.lowercased() } + ecosystems.map { $0.lowercased() } + [fullName.lowercased()])
            .joined(separator: " ")

        switch preset {
        case .localAIUIs:
            let keywords = ["ollama", "open webui", "open-webui", "librechat", "flowise", "langflow", "local ai", "llm ui", "chat ui"]
            let hits = keywordHits(keywords, in: haystack)
            if hits.isEmpty { return (0, "") }
            return (Double(hits.count) * 2.5 + (haystack.contains("local") ? 1.5 : 0), "Local AI stack/topic match: \(hits.joined(separator: ", "))")

        case .lowCodeBuilders:
            let keywords = ["tooljet", "budibase", "appsmith", "low-code", "low code", "internal tool", "app builder", "visual builder"]
            let hits = keywordHits(keywords, in: haystack)
            if hits.isEmpty { return (0, "") }
            return (Double(hits.count) * 2.2, "Low-code builder signals: \(hits.joined(separator: ", "))")

        case .macOSDesktopTools:
            let keywords = ["tauri", "electron", "swiftui", "appkit", "macos", "desktop", "native app"]
            let hits = keywordHits(keywords, in: haystack)
            if hits.isEmpty { return (0, "") }
            return (Double(hits.count) * 2.0 + (stackLower.contains(where: { $0.contains("swift") }) ? 1.0 : 0),
                    "Desktop tooling signals: \(hits.joined(separator: ", "))")

        case .mcpTools:
            let mcpStack = stackLower.contains(where: { $0.contains("mcp") })
            let mcpGraph = relationships.contains(where: { $0.targetLabel.localizedCaseInsensitiveContains("mcp") || $0.relationshipType.contains("mcp") })
            let mcpTopic = haystack.contains("mcp")
            guard mcpStack || mcpGraph || mcpTopic else { return (0, "") }
            var parts: [String] = []
            if mcpStack { parts.append("stack detection") }
            if mcpGraph { parts.append("graph relationship") }
            if mcpTopic { parts.append("topic/ecosystem") }
            return (4.0 + Double(parts.count), "MCP signals via \(parts.joined(separator: ", "))")

        case .databaseTools:
            let keywords = ["directus", "payload", "supabase", "postgres", "sqlite", "database", "cms", "headless cms", "orm"]
            let hits = keywordHits(keywords, in: haystack)
            if hits.isEmpty { return (0, "") }
            return (Double(hits.count) * 2.0, "Database/CMS signals: \(hits.joined(separator: ", "))")

        case .agentTooling:
            let keywords = ["langchain", "agent", "codex", "autogen", "crewai", "workflow", "tool calling", "mcp"]
            let hits = keywordHits(keywords, in: haystack)
            if hits.isEmpty && relationshipCount == 0 { return (0, "") }
            let graphBonus = relationshipCount > 0 ? min(Double(relationshipCount), 4.0) * 0.4 : 0
            return (Double(hits.count) * 1.8 + graphBonus,
                    hits.isEmpty ? "Connected in agent/workflow graph" : "Agent tooling signals: \(hits.joined(separator: ", "))")
        }
    }

    private static func keywordHits(_ keywords: [String], in haystack: String) -> [String] {
        keywords.filter { haystack.contains($0) }
    }

    private static func decodeTopics(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    private static func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}
