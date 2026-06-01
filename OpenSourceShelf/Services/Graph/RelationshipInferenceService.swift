import CryptoKit
import Foundation

struct GraphInferenceInput {
    var repository: RepositoryRecord
    var manifests: [RepositoryManifestRecord]
    var stackItems: [DetectedStackItemRecord]
    var aiInsight: AIInsightRecord?
}

struct GraphInferenceResult: Equatable {
    var nodes: [GraphNode]
    var edges: [GraphEdge]
}

enum RelationshipInferenceService {
    static let supportedNodeTypes: Set<String> = [
        "repository",
        "framework",
        "language",
        "runtime",
        "database",
        "ai_tool",
        "protocol",
        "workflow",
        "ecosystem"
    ]

    static let supportedRelationshipTypes: Set<String> = [
        "similar_to",
        "alternative_to",
        "integrates_with",
        "useful_for",
        "same_stack",
        "same_problem_space",
        "compatible_with",
        "implements_protocol",
        "depends_on"
    ]

    static func inferRelationships(input: GraphInferenceInput,
                                   createdAt: String) -> GraphInferenceResult {
        let repositoryNode = node(type: "repository",
                                  key: "repository:\(input.repository.id)",
                                  label: input.repository.fullName,
                                  metadata: [
                                      "githubURL": input.repository.githubURL,
                                      "repositoryID": input.repository.id
                                  ])
        var nodesByKey = [repositoryNode.key: repositoryNode]
        var edgesByID: [String: GraphEdge] = [:]

        func register(_ node: GraphNode) -> GraphNode {
            if let existing = nodesByKey[node.key] {
                return existing
            }
            nodesByKey[node.key] = node
            return node
        }

        func connect(target: GraphNode,
                     relationshipType: String,
                     confidence: Double,
                     evidenceText: String?,
                     evidencePath: String?,
                     createdBy: String) {
            guard supportedRelationshipTypes.contains(relationshipType) else { return }
            let targetNode = register(target)
            let edge = edge(source: repositoryNode,
                            target: targetNode,
                            relationshipType: relationshipType,
                            confidence: confidence,
                            evidenceText: evidenceText,
                            evidencePath: evidencePath,
                            createdBy: createdBy,
                            createdAt: createdAt)
            merge(edge, into: &edgesByID)
        }

        for item in input.stackItems {
            guard let target = node(for: item) else { continue }
            let relationshipType = relationshipType(for: item)
            let confidence = confidence(for: item)
            connect(target: target,
                    relationshipType: relationshipType,
                    confidence: confidence,
                    evidenceText: item.evidenceText ?? item.name,
                    evidencePath: item.evidencePath,
                    createdBy: item.detectionSource)

            for extra in extraRelationships(for: item) {
                connect(target: extra.node,
                        relationshipType: extra.relationshipType,
                        confidence: extra.confidence,
                        evidenceText: extra.evidenceText,
                        evidencePath: item.evidencePath,
                        createdBy: "deterministic_rule")
            }
        }

        for manifest in input.manifests {
            for inferred in relationships(for: manifest) {
                connect(target: inferred.node,
                        relationshipType: inferred.relationshipType,
                        confidence: inferred.confidence,
                        evidenceText: inferred.evidenceText,
                        evidencePath: manifest.path,
                        createdBy: "manifest")
            }
        }

        for hint in relationshipHints(from: input.aiInsight) {
            for inferred in relationships(forAIHint: hint) {
                connect(target: inferred.node,
                        relationshipType: inferred.relationshipType,
                        confidence: inferred.confidence,
                        evidenceText: hint,
                        evidencePath: nil,
                        createdBy: "ai_hint")
            }
        }

        return GraphInferenceResult(nodes: Array(nodesByKey.values).sorted { $0.key < $1.key },
                                    edges: Array(edgesByID.values).sorted { $0.id < $1.id })
    }

    private static func node(for item: DetectedStackItemRecord) -> GraphNode? {
        switch item.category {
        case "language":
            return namedNode(type: "language", label: item.name)
        case "framework", "desktop":
            return namedNode(type: "framework", label: item.name)
        case "runtime":
            return namedNode(type: "runtime", label: item.name)
        case "database":
            return namedNode(type: "database", label: item.name)
        case "ai_integration":
            return namedNode(type: "ai_tool", label: item.name)
        case "package_manager", "deployment", "tooling":
            return namedNode(type: "ecosystem", label: item.name)
        case "local_first":
            return namedNode(type: "workflow", label: "Local-first")
        default:
            return nil
        }
    }

    private static func relationshipType(for item: DetectedStackItemRecord) -> String {
        switch item.category {
        case "ai_integration":
            return "integrates_with"
        case "local_first":
            return "useful_for"
        case "deployment":
            return "compatible_with"
        default:
            return "same_stack"
        }
    }

    private static func confidence(for item: DetectedStackItemRecord) -> Double {
        if item.detectionSource == "manifest" {
            return max(item.confidence, 0.95)
        }
        if item.detectionSource == "dependency" {
            return max(item.confidence, 0.85)
        }
        return max(item.confidence, 0.65)
    }

    private static func extraRelationships(for item: DetectedStackItemRecord) -> [InferredRelationship] {
        let normalized = normalize(item.name)
        switch normalized {
        case "tauri":
            return [
                InferredRelationship(node: namedNode(type: "framework", label: "Electron"),
                                     relationshipType: "alternative_to",
                                     confidence: 0.75,
                                     evidenceText: "Tauri detected as a desktop framework alternative to Electron.")
            ]
        case "electron":
            return [
                InferredRelationship(node: namedNode(type: "framework", label: "Tauri"),
                                     relationshipType: "alternative_to",
                                     confidence: 0.75,
                                     evidenceText: "Electron detected as a desktop framework alternative to Tauri.")
            ]
        case "mcp":
            return [
                InferredRelationship(node: namedNode(type: "protocol", label: "MCP"),
                                     relationshipType: "implements_protocol",
                                     confidence: 0.85,
                                     evidenceText: "MCP stack signal detected.")
            ]
        case "ollama":
            return [
                InferredRelationship(node: namedNode(type: "workflow", label: "Local AI workflow"),
                                     relationshipType: "useful_for",
                                     confidence: 0.8,
                                     evidenceText: "Ollama integration indicates local AI workflow support.")
            ]
        default:
            return []
        }
    }

    private static func relationships(for manifest: RepositoryManifestRecord) -> [InferredRelationship] {
        let manifestType = manifest.type.lowercased()
        let ecosystem = manifest.ecosystem
        var results: [InferredRelationship] = []

        if !ecosystem.isEmpty {
            results.append(
                InferredRelationship(node: namedNode(type: "ecosystem", label: ecosystem),
                                     relationshipType: "same_stack",
                                     confidence: 0.95,
                                     evidenceText: "\(manifest.type) manifest detected.")
            )
        }

        if manifestType.contains("mcp") || manifest.path == "mcp.json" || manifest.path == "claude_desktop_config.json" {
            results.append(
                InferredRelationship(node: namedNode(type: "protocol", label: "MCP"),
                                     relationshipType: "implements_protocol",
                                     confidence: 0.95,
                                     evidenceText: "MCP configuration detected.")
            )
        }

        if manifestType.contains("docker") || manifest.path.lowercased().contains("docker") || manifest.path.lowercased().contains("compose") {
            results.append(
                InferredRelationship(node: namedNode(type: "ecosystem", label: "Docker"),
                                     relationshipType: "compatible_with",
                                     confidence: 0.95,
                                     evidenceText: "Docker or Compose manifest detected.")
            )
        }

        if manifestType.contains("tauri") || manifest.path.lowercased().contains("tauri") {
            results.append(
                InferredRelationship(node: namedNode(type: "framework", label: "Tauri"),
                                     relationshipType: "same_stack",
                                     confidence: 0.95,
                                     evidenceText: "Tauri configuration detected.")
            )
        }

        return results
    }

    private static func relationships(forAIHint hint: String) -> [InferredRelationship] {
        let lowercased = hint.lowercased()
        var results: [InferredRelationship] = []

        if lowercased.contains("ollama") {
            results.append(
                InferredRelationship(node: namedNode(type: "ai_tool", label: "Ollama"),
                                     relationshipType: lowercased.contains("pairs with") ? "compatible_with" : "integrates_with",
                                     confidence: 0.45,
                                     evidenceText: hint)
            )
        }

        if lowercased.contains("flowise") {
            results.append(
                InferredRelationship(node: externalRepositoryNode(label: "Flowise"),
                                     relationshipType: lowercased.contains("alternative") ? "alternative_to" : "similar_to",
                                     confidence: 0.45,
                                     evidenceText: hint)
            )
        }

        if lowercased.contains("electron") {
            results.append(
                InferredRelationship(node: namedNode(type: "framework", label: "Electron"),
                                     relationshipType: lowercased.contains("alternative") ? "alternative_to" : "compatible_with",
                                     confidence: 0.45,
                                     evidenceText: hint)
            )
        }

        if lowercased.contains("tauri") {
            results.append(
                InferredRelationship(node: namedNode(type: "framework", label: "Tauri"),
                                     relationshipType: lowercased.contains("alternative") ? "alternative_to" : "compatible_with",
                                     confidence: 0.45,
                                     evidenceText: hint)
            )
        }

        if lowercased.contains("mcp") {
            results.append(
                InferredRelationship(node: namedNode(type: "protocol", label: "MCP"),
                                     relationshipType: lowercased.contains("protocol") ? "implements_protocol" : "compatible_with",
                                     confidence: 0.45,
                                     evidenceText: hint)
            )
        }

        if lowercased.contains("local ai") {
            results.append(
                InferredRelationship(node: namedNode(type: "workflow", label: "Local AI workflow"),
                                     relationshipType: "useful_for",
                                     confidence: 0.45,
                                     evidenceText: hint)
            )
        }

        return results
    }

    private static func relationshipHints(from insight: AIInsightRecord?) -> [String] {
        guard let insight,
              let data = insight.relationshipHintsJSON.data(using: .utf8),
              let hints = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Array(Set(hints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted()
    }

    private static func namedNode(type: String, label: String) -> GraphNode {
        node(type: type, key: "\(type):\(normalize(label))", label: label, metadata: [:])
    }

    private static func externalRepositoryNode(label: String) -> GraphNode {
        node(type: "repository",
             key: "repository:external:\(normalize(label))",
             label: label,
             metadata: ["external": "true"])
    }

    private static func node(type: String,
                             key: String,
                             label: String,
                             metadata: [String: String]) -> GraphNode {
        GraphNode(id: stableID(prefix: "node", parts: [key]),
                  type: type,
                  key: key,
                  label: label,
                  metadataJSON: metadataJSON(metadata))
    }

    private static func edge(source: GraphNode,
                             target: GraphNode,
                             relationshipType: String,
                             confidence: Double,
                             evidenceText: String?,
                             evidencePath: String?,
                             createdBy: String,
                             createdAt: String) -> GraphEdge {
        GraphEdge(id: stableID(prefix: "edge", parts: [source.id, target.id, relationshipType]),
                  sourceNodeID: source.id,
                  targetNodeID: target.id,
                  relationshipType: relationshipType,
                  confidence: min(1, max(0, confidence)),
                  evidenceText: evidenceText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  evidencePath: evidencePath,
                  createdBy: createdBy,
                  createdAt: createdAt)
    }

    private static func merge(_ edge: GraphEdge, into edges: inout [String: GraphEdge]) {
        guard let existing = edges[edge.id] else {
            edges[edge.id] = edge
            return
        }
        if edge.confidence >= existing.confidence {
            edges[edge.id] = edge
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^a-z0-9+.#-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func stableID(prefix: String, parts: [String]) -> String {
        let raw = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "\(prefix)-\(digest.map { String(format: "%02x", $0) }.joined())"
    }

    private static func metadataJSON(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

private struct InferredRelationship {
    var node: GraphNode
    var relationshipType: String
    var confidence: Double
    var evidenceText: String?
}
