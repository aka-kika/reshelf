import Foundation

enum ComparisonScoringService {
    static func rank(profiles: [RepositoryComparisonProfile],
                     sharedStack: [String],
                     sharedEcosystems: [String]) -> [ComparisonRankingEntry] {
        let scored = profiles.map { profile -> (RepositoryComparisonProfile, Double, [String], [String]) in
            var signals: [(String, Double)] = []
            if let value = profile.personalRelevance {
                signals.append(("Personal relevance \(value)/10", Double(value) * 1.4))
            }
            if let value = profile.localFirstScore {
                signals.append(("Local-first \(value)/10", Double(value) * 1.3))
            }
            if let value = profile.experimentationPriority {
                signals.append(("Experimentation \(value)/10", Double(value) * 1.0))
            }
            if let value = profile.setupComplexity {
                let inverse = max(0, 11 - value)
                signals.append(("Lower setup complexity", Double(inverse) * 1.1))
            }
            if profile.graphCentrality > 0 {
                signals.append(("Graph centrality", Double(min(profile.graphCentrality, 24)) * 0.35))
            }
            if profile.recommendationCount > 0 {
                signals.append(("Recommendation strength", Double(min(profile.recommendationCount, 8)) * 0.8))
            }
            let ecosystemFit = profile.ecosystemNames.filter { sharedEcosystems.contains($0) }.count
            if ecosystemFit > 0 {
                signals.append(("Ecosystem fit", Double(ecosystemFit) * 1.5))
            }
            let stackOverlap = profile.stackItems.filter { sharedStack.contains($0) }.count
            if stackOverlap > 0 {
                signals.append(("Shared stack overlap", Double(stackOverlap) * 0.6))
            }
            if profile.hasMCP {
                signals.append(("MCP support detected", 2.0))
            }
            if profile.hasAIIntegration {
                signals.append(("AI integration detected", 1.5))
            }

            let composite = signals.map(\.1).reduce(0, +)
            let strongest = signals.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            let weakest = signals.sorted { $0.1 < $1.1 }.prefix(2).map(\.0)
            return (profile, composite, strongest, weakest)
        }

        let ordered = scored.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.fullName < rhs.0.fullName }
            return lhs.1 > rhs.1
        }

        return ordered.enumerated().map { index, entry in
            ComparisonRankingEntry(
                repositoryID: entry.0.repositoryID,
                fullName: entry.0.fullName,
                rank: index + 1,
                compositeScore: entry.1,
                strongestSignals: entry.2,
                weakestSignals: entry.3,
                explanation: "Ranked #\(index + 1) from deterministic score signals across local-first fit, setup complexity, graph centrality, and stack overlap."
            )
        }
    }
}
