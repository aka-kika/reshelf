import CryptoKit
import Foundation

struct EcosystemDiscoveryInput {
    var repositories: [EcosystemRepositoryFact]
    var stackItems: [EcosystemStackFact]
    var relationships: [EcosystemRelationshipFact]
    var recommendations: [EcosystemRecommendationFact]
    var scores: [String: RepositoryScoreRecord]
    var classificationsByRepositoryID: [String: [String]]
}

struct EcosystemRepositoryFact: Equatable {
    var id: String
    var fullName: String
    var name: String
}

struct EcosystemStackFact: Equatable {
    var repositoryID: String
    var name: String
    var category: String
    var confidence: Double
}

struct EcosystemRelationshipFact: Equatable {
    var sourceRepositoryID: String
    var relationshipType: String
    var targetLabel: String
    var targetType: String
    var confidence: Double
}

struct EcosystemRecommendationFact: Equatable {
    var sourceRepositoryID: String
    var recommendationType: String
    var targetLabel: String
    var score: Double
    var explanation: String
}

enum WorkflowClusterService {
    static func makeClusters(input: EcosystemDiscoveryInput,
                             cacheKey: String,
                             generatedAt: String) -> [EcosystemClusterRecord] {
        var clusters = ecosystemDefinitions().compactMap { definition in
            makeCluster(definition: definition, input: input, cacheKey: cacheKey, generatedAt: generatedAt)
        }
        clusters.append(contentsOf: makeStackOverviewClusters(input: input, cacheKey: cacheKey, generatedAt: generatedAt))
        return clusters
            .filter(hasContent)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.name < rhs.name
                }
                return lhs.score > rhs.score
            }
    }

    private static func makeCluster(definition: EcosystemDefinition,
                                    input: EcosystemDiscoveryInput,
                                    cacheKey: String,
                                    generatedAt: String) -> EcosystemClusterRecord? {
        let matchedRepositories = input.repositories.filter { repository in
            let text = evidenceText(repositoryID: repository.id, repository: repository, input: input)
            return definition.keywords.contains { keywordMatches($0, in: text) }
        }

        guard !matchedRepositories.isEmpty else {
            return nil
        }

        let repositoryIDs = Set(matchedRepositories.map(\.id))
        let stack = input.stackItems.filter { repositoryIDs.contains($0.repositoryID) }
        let relationships = input.relationships.filter { repositoryIDs.contains($0.sourceRepositoryID) }
        let recommendations = input.recommendations.filter { repositoryIDs.contains($0.sourceRepositoryID) }
        let scores = repositoryIDs.compactMap { input.scores[$0] }

        let averageConfidence = average(relationships.map(\.confidence) + stack.map(\.confidence))
        let averageRecommendationScore = average(recommendations.map(\.score))
        let rankingInput = EcosystemRankingInput(
            repositoryCount: matchedRepositories.count,
            relationshipCount: relationships.count,
            averageConfidence: averageConfidence,
            averageRecommendationScore: averageRecommendationScore,
            averagePersonalRelevance: average(scores.map { Double($0.personalRelevance) }),
            averageLocalFirstScore: average(scores.map { Double($0.localFirstScore) }),
            averageExperimentationPriority: average(scores.map { Double($0.experimentationPriority) })
        )

        let score = EcosystemRankingService.rank(rankingInput)
        let confidence = EcosystemRankingService.confidence(repositoryCount: matchedRepositories.count,
                                                            averageConfidence: averageConfidence,
                                                            relationshipCount: relationships.count)
        let commonStack = topValues(stack.map(\.name), limit: 8)
        let strongestTools = topValues((stack.map(\.name) + relationships.map(\.targetLabel)), limit: 8)
        let integrations = topValues(relationships
            .filter { ["integrates_with", "compatible_with", "implements_protocol"].contains($0.relationshipType) }
            .map(\.targetLabel), limit: 6)
        let highlights = recommendations
            .sorted { $0.score > $1.score }
            .prefix(4)
            .map { "\($0.targetLabel): \($0.explanation)" }
        let missingPieces = missingPieces(for: definition, stackNames: Set(stack.map { $0.name.lowercased() }), relationships: relationships)
        let signals = [
            "\(matchedRepositories.count) repositories",
            "\(relationships.count) relationships",
            "average confidence \(Int((averageConfidence * 100).rounded()))%",
            "average recommendation \(Int(averageRecommendationScore.rounded()))"
        ]

        return EcosystemClusterRecord(
            id: stableID(parts: [definition.clusterType, definition.name]),
            clusterType: definition.clusterType,
            name: definition.name,
            score: score,
            confidence: confidence,
            repositoryIDsJSON: encode(matchedRepositories.map(\.id)),
            repositoryNamesJSON: encode(matchedRepositories.map(\.fullName).sorted()),
            commonStackJSON: encode(commonStack),
            strongestToolsJSON: encode(strongestTools),
            integrationsJSON: encode(integrations),
            recommendationHighlightsJSON: encode(Array(highlights)),
            missingPiecesJSON: encode(missingPieces),
            signalsJSON: encode(signals),
            explanation: explanation(for: definition, repositoryCount: matchedRepositories.count, commonStack: commonStack),
            cacheKey: cacheKey,
            generatedAt: generatedAt
        )
    }

    private static func makeStackOverviewClusters(input: EcosystemDiscoveryInput,
                                                  cacheKey: String,
                                                  generatedAt: String) -> [EcosystemClusterRecord] {
        let centralRepositories = input.recommendations
            .reduce(into: [String: Double]()) { totals, recommendation in
                totals[recommendation.sourceRepositoryID, default: 0] += recommendation.score
            }
            .sorted { $0.value > $1.value }
            .prefix(6)
            .compactMap { id, _ in input.repositories.first { $0.id == id } }

        let commonTechnologies = topValues(input.stackItems.map(\.name), limit: 10)
        let highConfidenceRelationships = input.relationships
            .filter { $0.confidence >= 0.75 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(8)
            .map { "\($0.targetLabel) (\(Int(($0.confidence * 100).rounded()))%)" }
        let experimentRepos = input.scores
            .sorted { $0.value.experimentationPriority > $1.value.experimentationPriority }
            .prefix(6)
            .compactMap { id, _ in input.repositories.first { $0.id == id }?.fullName }

        return [
            makeOverview(name: "Most central repos",
                         repositoryNames: centralRepositories.map(\.fullName),
                         commonStack: commonTechnologies,
                         highlights: highConfidenceRelationships,
                         score: min(100, Double(centralRepositories.count * 12) + Double(input.recommendations.count)),
                         explanation: "Repositories with the strongest recommendation and relationship activity.",
                         cacheKey: cacheKey,
                         generatedAt: generatedAt),
            makeOverview(name: "Strongest technologies",
                         repositoryNames: [],
                         commonStack: commonTechnologies,
                         highlights: highConfidenceRelationships,
                         score: min(100, Double(commonTechnologies.count * 8)),
                         explanation: "Technologies that appear most often across stack detections.",
                         cacheKey: cacheKey,
                         generatedAt: generatedAt),
            makeOverview(name: "Current experimentation areas",
                         repositoryNames: experimentRepos,
                         commonStack: commonTechnologies,
                         highlights: [],
                         score: min(100, Double(experimentRepos.count * 12)),
                         explanation: "Repos with the strongest experimentation-priority signals.",
                         cacheKey: cacheKey,
                         generatedAt: generatedAt)
        ]
    }

    private static func makeOverview(name: String,
                                     repositoryNames: [String],
                                     commonStack: [String],
                                     highlights: [String],
                                     score: Double,
                                     explanation: String,
                                     cacheKey: String,
                                     generatedAt: String) -> EcosystemClusterRecord {
        EcosystemClusterRecord(
            id: stableID(parts: ["my_stack", name]),
            clusterType: "my_stack",
            name: name,
            score: score,
            confidence: min(1, score / 100),
            repositoryIDsJSON: "[]",
            repositoryNamesJSON: encode(repositoryNames),
            commonStackJSON: encode(commonStack),
            strongestToolsJSON: encode(commonStack),
            integrationsJSON: "[]",
            recommendationHighlightsJSON: encode(highlights),
            missingPiecesJSON: "[]",
            signalsJSON: encode(["stack overview", "recommendation activity"]),
            explanation: explanation,
            cacheKey: cacheKey,
            generatedAt: generatedAt
        )
    }

    private static func ecosystemDefinitions() -> [EcosystemDefinition] {
        [
            EcosystemDefinition(clusterType: "ecosystem", name: "Local AI", keywords: ["ollama", "local ai", "llm", "open webui", "mlx"]),
            EcosystemDefinition(clusterType: "ecosystem", name: "MCP ecosystem", keywords: ["mcp", "model context protocol"]),
            EcosystemDefinition(clusterType: "ecosystem", name: "Agent tooling", keywords: ["agent", "langchain", "langgraph", "autonomous", "orchestration"]),
            EcosystemDefinition(clusterType: "ecosystem", name: "macOS desktop tools", keywords: ["macos", "swiftui", "tauri", "electron", "desktop"]),
            EcosystemDefinition(clusterType: "ecosystem", name: "Database tooling", keywords: ["postgres", "sqlite", "supabase", "database", "redis", "mongodb"]),
            EcosystemDefinition(clusterType: "workflow", name: "Automation workflows", keywords: ["workflow", "automation", "queue", "scheduler", "n8n"]),
            EcosystemDefinition(clusterType: "workflow", name: "Content workflows", keywords: ["content", "markdown", "docs", "blog", "cms"]),
            EcosystemDefinition(clusterType: "ecosystem", name: "Developer infrastructure", keywords: ["docker", "deployment", "wrangler", "vercel", "cloudflare", "github actions"]),
            EcosystemDefinition(clusterType: "ecosystem", name: "Local-first apps", keywords: ["local-first", "local first", "sqlite", "offline", "self-hosted"]),
            EcosystemDefinition(clusterType: "workflow", name: "AI workflow builders", keywords: ["flowise", "langflow", "n8n", "workflow builder", "agent builder"])
        ]
    }

    private static func evidenceText(repositoryID: String,
                                     repository: EcosystemRepositoryFact,
                                     input: EcosystemDiscoveryInput) -> String {
        let stack = input.stackItems.filter { $0.repositoryID == repositoryID }.map(\.name)
        let relationships = input.relationships.filter { $0.sourceRepositoryID == repositoryID }.flatMap { [$0.targetLabel, $0.relationshipType] }
        let recommendations = input.recommendations.filter { $0.sourceRepositoryID == repositoryID }.flatMap { [$0.targetLabel, $0.explanation, $0.recommendationType] }
        let classifications = input.classificationsByRepositoryID[repositoryID] ?? []
        return ([repository.fullName, repository.name] + stack + relationships + recommendations + classifications)
            .joined(separator: " ")
            .lowercased()
    }

    private static func keywordMatches(_ keyword: String, in text: String) -> Bool {
        let normalizedKeyword = keyword.lowercased()
        if normalizedKeyword.contains(" ") || normalizedKeyword.contains("-") {
            return text.contains(normalizedKeyword)
        }
        if normalizedKeyword.count <= 3 {
            return tokenSet(text).contains(normalizedKeyword)
        }
        return text.contains(normalizedKeyword)
    }

    private static func tokenSet(_ text: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        return Set(text.components(separatedBy: separators).filter { !$0.isEmpty })
    }

    private static func hasContent(_ cluster: EcosystemClusterRecord) -> Bool {
        !decode(cluster.repositoryIDsJSON).isEmpty
            || !decode(cluster.repositoryNamesJSON).isEmpty
            || !decode(cluster.commonStackJSON).isEmpty
            || !decode(cluster.recommendationHighlightsJSON).isEmpty
    }

    private static func explanation(for definition: EcosystemDefinition,
                                    repositoryCount: Int,
                                    commonStack: [String]) -> String {
        let stack = commonStack.prefix(3).joined(separator: ", ")
        if stack.isEmpty {
            return "\(definition.name) is emerging from \(repositoryCount) repository signal\(repositoryCount == 1 ? "" : "s")."
        }
        return "\(definition.name) is emerging from \(repositoryCount) repositories around \(stack)."
    }

    private static func missingPieces(for definition: EcosystemDefinition,
                                      stackNames: Set<String>,
                                      relationships: [EcosystemRelationshipFact]) -> [String] {
        let text = (Array(stackNames) + relationships.map(\.targetLabel)).joined(separator: " ").lowercased()
        switch definition.name {
        case "Local AI":
            if text.contains("ollama") && !text.contains("flowise") && !text.contains("langflow") && !text.contains("n8n") {
                return ["Your local AI stack has Ollama signals but no workflow builder yet."]
            }
        case "MCP ecosystem":
            if text.contains("mcp") && !text.contains("inspector") {
                return ["Multiple MCP signals detected, but no MCP inspector/debugging tool is visible yet."]
            }
        case "Agent tooling":
            if text.contains("agent") && !text.contains("evaluation") && !text.contains("eval") {
                return ["Agent tooling is present, but evaluation or regression tooling is not yet obvious."]
            }
        case "macOS desktop tools":
            if (text.contains("tauri") || text.contains("electron") || text.contains("swiftui")) && !text.contains("sparkle") {
                return ["Desktop tooling is emerging, but update/distribution tooling is not yet visible."]
            }
        case "Database tooling":
            if text.contains("postgres") && !text.contains("migration") {
                return ["Database tooling is present, but migration workflow tools are not obvious yet."]
            }
        default:
            return []
        }
        return []
    }

    private static func topValues(_ values: [String], limit: Int) -> [String] {
        Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
            .map { (value: $0.key, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count {
                    return $0.value < $1.value
                }
                return $0.count > $1.count
            }
            .prefix(limit)
            .map(\.value)
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func encode(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    private static func stableID(parts: [String]) -> String {
        let raw = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "ecosystem-\(digest.map { String(format: "%02x", $0) }.joined())"
    }
}

private struct EcosystemDefinition {
    var clusterType: String
    var name: String
    var keywords: [String]
}
