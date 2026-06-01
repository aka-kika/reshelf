import Foundation

enum ComparisonExplanationService {
    static func sharedStack(from profiles: [RepositoryComparisonProfile]) -> [String] {
        guard let first = profiles.first else { return [] }
        let sets = profiles.map { Set($0.stackItems) }
        return sets.dropFirst().reduce(Set(first.stackItems)) { $0.intersection($1) }.sorted()
    }

    static func uniqueStack(from profiles: [RepositoryComparisonProfile],
                            shared: [String]) -> [String: [String]] {
        let sharedSet = Set(shared)
        var result: [String: [String]] = [:]
        for profile in profiles {
            result[profile.repositoryID] = profile.stackItems.filter { !sharedSet.contains($0) }.sorted()
        }
        return result
    }

    static func sharedEcosystems(from profiles: [RepositoryComparisonProfile]) -> [String] {
        guard let first = profiles.first else { return [] }
        let sets = profiles.map { Set($0.ecosystemNames) }
        return sets.dropFirst().reduce(Set(first.ecosystemNames)) { $0.intersection($1) }.sorted()
    }

    static func uniqueRisks(from profiles: [RepositoryComparisonProfile]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for profile in profiles {
            result[profile.repositoryID] = profile.risks
        }
        return result
    }

    static func uniqueStrengths(from profiles: [RepositoryComparisonProfile]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for profile in profiles {
            var strengths: [String] = []
            if let score = profile.localFirstScore, score >= 7 {
                strengths.append("Strong local-first score (\(score)/10)")
            }
            if let score = profile.experimentationPriority, score >= 7 {
                strengths.append("High experimentation priority (\(score)/10)")
            }
            if profile.graphCentrality >= 4 {
                strengths.append("Well connected in your graph (\(profile.graphCentrality) edges)")
            }
            if profile.hasMCP {
                strengths.append("MCP-compatible signals detected")
            }
            if let usefulness = profile.usefulness, !usefulness.isEmpty {
                strengths.append(usefulness)
            }
            result[profile.repositoryID] = strengths
        }
        return result
    }

    static func decisionSummary(profiles: [RepositoryComparisonProfile],
                                rankings: [ComparisonRankingEntry]) -> [ComparisonDecisionLine] {
        guard !profiles.isEmpty else { return [] }
        var lines: [ComparisonDecisionLine] = []

        if let winner = profiles.max(by: { ($0.localFirstScore ?? 0) < ($1.localFirstScore ?? 0) }),
           let score = winner.localFirstScore, score > 0 {
            lines.append(ComparisonDecisionLine(
                category: "Best local-first fit",
                winnerRepositoryID: winner.repositoryID,
                winnerLabel: winner.fullName,
                explanation: "Highest local-first score (\(score)/10) from persisted repository scoring."
            ))
        }

        if let winner = profiles.min(by: { ($0.setupComplexity ?? 99) < ($1.setupComplexity ?? 99) }),
           let complexity = winner.setupComplexity {
            lines.append(ComparisonDecisionLine(
                category: "Easiest to test",
                winnerRepositoryID: winner.repositoryID,
                winnerLabel: winner.fullName,
                explanation: "Lowest setup complexity (\(complexity)/10) among selected repos."
            ))
        }

        if let winner = profiles.max(by: { ($0.experimentationPriority ?? 0) < ($1.experimentationPriority ?? 0) }),
           let value = winner.experimentationPriority, value > 0 {
            lines.append(ComparisonDecisionLine(
                category: "Best for experimentation",
                winnerRepositoryID: winner.repositoryID,
                winnerLabel: winner.fullName,
                explanation: "Highest experimentation priority (\(value)/10)."
            ))
        }

        if let winner = profiles.max(by: { $0.graphCentrality < $1.graphCentrality }),
           winner.graphCentrality > 0 {
            lines.append(ComparisonDecisionLine(
                category: "Strongest graph overlap",
                winnerRepositoryID: winner.repositoryID,
                winnerLabel: winner.fullName,
                explanation: "Most connected in your shelf graph (\(winner.graphCentrality) relationships)."
            ))
        }

        if let topRank = rankings.first {
            lines.append(ComparisonDecisionLine(
                category: "Overall recommendation",
                winnerRepositoryID: topRank.repositoryID,
                winnerLabel: topRank.fullName,
                explanation: topRank.explanation
            ))
        }

        return Array(lines.prefix(6))
    }

    static func matrixRows(from profiles: [RepositoryComparisonProfile]) -> [ComparisonMatrixRow] {
        let valueMap: (String) -> [String: String] = { key in
            Dictionary(uniqueKeysWithValues: profiles.map { profile in
                (profile.repositoryID, matrixValue(for: key, profile: profile))
            })
        }

        return [
            ComparisonMatrixRow(key: "summary", label: "Summary", values: valueMap("summary")),
            ComparisonMatrixRow(key: "purpose", label: "Primary purpose", values: valueMap("purpose")),
            ComparisonMatrixRow(key: "language", label: "Language", values: valueMap("language")),
            ComparisonMatrixRow(key: "frameworks", label: "Frameworks", values: valueMap("frameworks")),
            ComparisonMatrixRow(key: "runtime", label: "Runtime", values: valueMap("runtime")),
            ComparisonMatrixRow(key: "package_manager", label: "Package manager", values: valueMap("package_manager")),
            ComparisonMatrixRow(key: "database", label: "Database usage", values: valueMap("database")),
            ComparisonMatrixRow(key: "ai", label: "AI integrations", values: valueMap("ai")),
            ComparisonMatrixRow(key: "mcp", label: "MCP support", values: valueMap("mcp")),
            ComparisonMatrixRow(key: "local_first", label: "Local-first score", values: valueMap("local_first")),
            ComparisonMatrixRow(key: "setup", label: "Setup complexity", values: valueMap("setup")),
            ComparisonMatrixRow(key: "experimentation", label: "Experimentation priority", values: valueMap("experimentation")),
            ComparisonMatrixRow(key: "personal", label: "Personal relevance", values: valueMap("personal")),
            ComparisonMatrixRow(key: "production", label: "Production readiness", values: valueMap("production")),
            ComparisonMatrixRow(key: "ecosystem", label: "Ecosystem membership", values: valueMap("ecosystem")),
            ComparisonMatrixRow(key: "centrality", label: "Graph centrality", values: valueMap("centrality")),
            ComparisonMatrixRow(key: "clone", label: "Clone status", values: valueMap("clone")),
            ComparisonMatrixRow(key: "analyzed", label: "Last analysis date", values: valueMap("analyzed"))
        ]
    }

    private static func matrixValue(for key: String, profile: RepositoryComparisonProfile) -> String {
        switch key {
        case "summary":
            return profile.summary ?? profile.description ?? "—"
        case "purpose":
            return profile.classifications.first ?? profile.usefulness ?? "—"
        case "language":
            return profile.primaryLanguage ?? "—"
        case "frameworks":
            return join(profile.stackByCategory["framework"] ?? profile.stackByCategory["frontend"] ?? [])
        case "runtime":
            return join(profile.stackByCategory["runtime"] ?? profile.stackByCategory["language"] ?? [])
        case "package_manager":
            return join(profile.stackByCategory["package_manager"] ?? [])
        case "database":
            return join(profile.stackByCategory["database"] ?? [])
        case "ai":
            return profile.hasAIIntegration ? join(profile.stackByCategory["ai"] ?? profile.stackItems.filter { $0.localizedCaseInsensitiveContains("ollama") || $0.localizedCaseInsensitiveContains("openai") }) : "—"
        case "mcp":
            return profile.hasMCP ? "Detected" : "—"
        case "local_first":
            return profile.localFirstScore.map { "\($0)/10" } ?? "—"
        case "setup":
            return profile.setupComplexity.map { "\($0)/10" } ?? "—"
        case "experimentation":
            return profile.experimentationPriority.map { "\($0)/10" } ?? "—"
        case "personal":
            return profile.personalRelevance.map { "\($0)/10" } ?? "—"
        case "production":
            return profile.productionReadiness
        case "ecosystem":
            return join(profile.ecosystemNames)
        case "centrality":
            return "\(profile.graphCentrality)"
        case "clone":
            return profile.cloneStatus ?? "—"
        case "analyzed":
            return profile.lastAnalyzedAt ?? "—"
        default:
            return "—"
        }
    }

    private static func join(_ values: [String]) -> String {
        values.isEmpty ? "—" : values.joined(separator: ", ")
    }
}
