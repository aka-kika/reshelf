import Foundation

struct RecommendationCandidate: Equatable {
    var signal: GraphRecommendationSignal
    var targetRepositoryID: String?
    var recommendationType: String
    var score: Double
    var explanation: String
    var signals: [String]
}

struct RecommendationScoringContext {
    var sourceStackItems: [DetectedStackItemRecord]
    var sourceScore: RepositoryScoreRecord?
    var sourceCloneState: CloneStateRecord?
    var targetStackItems: [DetectedStackItemRecord]
    var targetScore: RepositoryScoreRecord?
    var targetCloneState: CloneStateRecord?
}

enum RelationshipScoringService {
    static func score(signal: GraphRecommendationSignal,
                      context: RecommendationScoringContext) -> RecommendationCandidate? {
        guard let recommendationType = recommendationType(for: signal) else {
            return nil
        }

        let overlap = stackOverlap(source: context.sourceStackItems, target: context.targetStackItems)
        var signals: [String] = []
        var score = 0.0

        let confidencePoints = signal.confidence * 45
        score += confidencePoints
        signals.append("relationship confidence \(Int((signal.confidence * 100).rounded()))%")

        let typeWeight = relationshipTypeWeight(signal.relationshipType)
        score += typeWeight
        signals.append("\(signal.relationshipType.replacingOccurrences(of: "_", with: " ")) signal")

        if signal.createdBy != "ai_hint" {
            score += 12
            signals.append("deterministic evidence")
        } else {
            score += 3
            signals.append("AI hint only")
        }

        if overlap.count > 0 {
            score += min(18, Double(overlap.count * 6))
            signals.append("stack overlap: \(overlap.prefix(4).joined(separator: ", "))")
        }

        if let sourceScore = context.sourceScore {
            score += Double(sourceScore.localFirstScore) * 1.2
            score += Double(sourceScore.experimentationPriority) * 1.1
            score += Double(sourceScore.personalRelevance)
            if sourceScore.localFirstScore >= 7 {
                signals.append("strong local-first fit")
            }
        }

        if let targetScore = context.targetScore {
            score += Double(targetScore.ecosystemInfluence) * 0.8
            score += Double(targetScore.personalRelevance) * 0.9
            if targetScore.experimentationPriority >= 7 {
                signals.append("target has high experimentation priority")
            }
        }

        if context.targetCloneState?.status == "cloned" {
            score += 4
            signals.append("target is already cloned")
        }
        if context.sourceCloneState?.status == "cloned" {
            score += 2
            signals.append("source is locally available")
        }

        score = min(100, max(0, score))
        let explanation = explanation(for: signal,
                                      recommendationType: recommendationType,
                                      overlap: overlap,
                                      deterministic: signal.createdBy != "ai_hint")

        return RecommendationCandidate(signal: signal,
                                       targetRepositoryID: targetRepositoryID(from: signal.targetKey),
                                       recommendationType: recommendationType,
                                       score: score,
                                       explanation: explanation,
                                       signals: Array(signals.prefix(8)))
    }

    private static func recommendationType(for signal: GraphRecommendationSignal) -> String? {
        switch signal.relationshipType {
        case "similar_to":
            return "related_repo"
        case "alternative_to":
            return "alternative"
        case "integrates_with":
            return signal.targetType == "repository" ? "related_repo" : "complementary_tool"
        case "compatible_with":
            if isDesktopTooling(signal.targetLabel) {
                return "desktop_tooling"
            }
            return "pairs_well_with"
        case "same_stack":
            if signal.targetType == "workflow" {
                return "same_workflow"
            }
            if ["ai_tool", "protocol"].contains(signal.targetType) {
                return signal.targetLabel.lowercased().contains("mcp") ? "mcp_compatible" : "ai_tooling_stack"
            }
            if isDesktopTooling(signal.targetLabel) {
                return "desktop_tooling"
            }
            return "same_ecosystem"
        case "same_problem_space":
            return "related_repo"
        case "useful_for":
            let lowercased = signal.targetLabel.lowercased()
            if lowercased.contains("local") {
                return "local_first_stack"
            }
            return "same_workflow"
        case "implements_protocol":
            return signal.targetLabel.lowercased().contains("mcp") ? "mcp_compatible" : "same_ecosystem"
        case "depends_on":
            return "complementary_tool"
        default:
            return nil
        }
    }

    private static func relationshipTypeWeight(_ relationshipType: String) -> Double {
        switch relationshipType {
        case "integrates_with":
            return 18
        case "implements_protocol":
            return 17
        case "alternative_to":
            return 16
        case "compatible_with":
            return 15
        case "same_stack":
            return 13
        case "useful_for":
            return 12
        case "similar_to":
            return 11
        case "same_problem_space":
            return 10
        case "depends_on":
            return 9
        default:
            return 5
        }
    }

    private static func isDesktopTooling(_ label: String) -> Bool {
        let lowercased = label.lowercased()
        return lowercased.contains("electron")
            || lowercased.contains("tauri")
            || lowercased.contains("swiftui")
            || lowercased.contains("desktop")
    }

    private static func stackOverlap(source: [DetectedStackItemRecord],
                                     target: [DetectedStackItemRecord]) -> [String] {
        let sourceNames = Set(source.map { normalized($0.name) })
        var targetNames: [String: String] = [:]
        for item in target {
            targetNames[normalized(item.name)] = item.name
        }
        return sourceNames
            .intersection(Set(targetNames.keys))
            .compactMap { targetNames[$0] }
            .sorted()
    }

    private static func explanation(for signal: GraphRecommendationSignal,
                                    recommendationType: String,
                                    overlap: [String],
                                    deterministic: Bool) -> String {
        if !overlap.isEmpty {
            return "Uses overlapping stack: \(overlap.prefix(4).joined(separator: ", "))."
        }

        let evidence = deterministic
            ? "High confidence relationship from deterministic evidence."
            : "Lower confidence relationship from AI relationship hints."

        switch recommendationType {
        case "alternative":
            return "\(signal.targetLabel) appears as an alternative based on \(signal.relationshipType.replacingOccurrences(of: "_", with: " "))."
        case "complementary_tool", "pairs_well_with":
            return "\(signal.targetLabel) pairs with this repository. \(evidence)"
        case "local_first_stack":
            return "Fits a local-first workflow. \(evidence)"
        case "ai_tooling_stack":
            return "Fits the AI tooling stack through \(signal.targetLabel)."
        case "mcp_compatible":
            return "MCP-compatible relationship detected. \(evidence)"
        case "desktop_tooling":
            return "Part of the desktop tooling ecosystem."
        default:
            return "\(signal.targetLabel) is related through \(signal.relationshipType.replacingOccurrences(of: "_", with: " ")). \(evidence)"
        }
    }

    private static func targetRepositoryID(from key: String) -> String? {
        guard key.hasPrefix("repository:") else {
            return nil
        }
        let id = String(key.dropFirst("repository:".count))
        return id.hasPrefix("external:") ? nil : id
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
