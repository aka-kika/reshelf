import Foundation
import CryptoKit

enum RepositoryCompareService {
    static let minRepositories = 2
    static let maxRepositories = 4

    static func buildComparison(repositoryIDs: [String],
                                database: IntelligenceDatabase = .shared) async throws -> RepositoryComparisonResult {
        try database.initialize()
        let ids = Array(Set(repositoryIDs)).sorted()
        guard ids.count >= minRepositories, ids.count <= maxRepositories else {
            throw RepositoryCompareError.invalidSelection
        }

        let signature = try database.comparisonEvidenceSignature(repositoryIDs: ids)
        let cacheKey = sha256(signature)

        if let cached = try database.fetchComparisonResultsCache(cacheSignature: cacheKey),
           let result = decodeResult(cached.resultJSON),
           result.cacheSignature == signature {
            return result
        }

        let profiles = try await Task.detached {
            try ids.map { try loadProfile(repositoryID: $0, database: database) }
        }.value

        let sharedStack = ComparisonExplanationService.sharedStack(from: profiles)
        let uniqueStack = ComparisonExplanationService.uniqueStack(from: profiles, shared: sharedStack)
        let sharedEcosystems = ComparisonExplanationService.sharedEcosystems(from: profiles)
        let rankings = ComparisonScoringService.rank(profiles: profiles,
                                                     sharedStack: sharedStack,
                                                     sharedEcosystems: sharedEcosystems)
        let graphOverlap = try await graphOverlap(for: profiles, database: database)
        let decisionSummary = ComparisonExplanationService.decisionSummary(profiles: profiles, rankings: rankings)
        let matrixRows = ComparisonExplanationService.matrixRows(from: profiles)

        let result = RepositoryComparisonResult(
            profiles: profiles,
            rankings: rankings,
            sharedStack: sharedStack,
            uniqueStack: uniqueStack,
            sharedEcosystems: sharedEcosystems,
            uniqueRisks: ComparisonExplanationService.uniqueRisks(from: profiles),
            uniqueStrengths: ComparisonExplanationService.uniqueStrengths(from: profiles),
            graphOverlap: graphOverlap,
            decisionSummary: decisionSummary,
            matrixRows: matrixRows,
            cacheSignature: signature,
            generatedAt: IntelligenceDatabase.iso8601String()
        )

        let record = ComparisonResultsCacheRecord(
            cacheSignature: cacheKey,
            repositoryIDsJSON: encodeStringArray(ids),
            resultJSON: encodeResult(result),
            createdAt: IntelligenceDatabase.iso8601String()
        )
        try database.upsertComparisonResultsCache(record)
        try persistSession(repositoryIDs: ids, database: database)

        return result
    }

    static func fetchCandidates(database: IntelligenceDatabase = .shared) throws -> [CompareFocusCandidate] {
        try database.initialize()
        return try database.fetchCompareFocusCandidates()
    }

    static func searchRepositories(query: String,
                                   database: IntelligenceDatabase = .shared) throws -> [RepositoryRecord] {
        try database.initialize()
        return try database.searchCompareRepositories(query: query)
    }

    static func recentSessions(database: IntelligenceDatabase = .shared) throws -> [ComparisonSessionRecord] {
        try database.initialize()
        return try database.fetchRecentComparisonSessions()
    }

    static func favoriteSessions(database: IntelligenceDatabase = .shared) throws -> [ComparisonSessionRecord] {
        try database.initialize()
        return try database.fetchFavoriteComparisonSessions()
    }

    static func setSessionFavorite(sessionID: String, isFavorite: Bool,
                                   database: IntelligenceDatabase = .shared) throws {
        try database.initialize()
        try database.setComparisonSessionFavorite(id: sessionID, isFavorite: isFavorite)
    }

    static func sessionID(for repositoryIDs: [String]) -> String {
        repositoryIDs.sorted().joined(separator: "|")
    }

    static func repositoryIDsForSimilar(sourceRepositoryID: String,
                                        database: IntelligenceDatabase = .shared) throws -> [String] {
        try database.initialize()
        var ids = Set([sourceRepositoryID])
        let similar = try database.fetchGraphRelationships(repositoryID: sourceRepositoryID,
                                                           relationshipTypes: ["similar_to", "same_problem_space", "same_stack"])
            .prefix(3)
        for relationship in similar {
            if let repositoryID = extractRepositoryID(from: relationship.targetKey) {
                ids.insert(repositoryID)
            }
        }
        return Array(ids.prefix(maxRepositories))
    }

    static func repositoryIDsForAlternatives(sourceRepositoryID: String,
                                             database: IntelligenceDatabase = .shared) throws -> [String] {
        try database.initialize()
        var ids = Set([sourceRepositoryID])
        let alternatives = try database.fetchAlternatives(repositoryID: sourceRepositoryID).prefix(3)
        for relationship in alternatives {
            if let repositoryID = extractRepositoryID(from: relationship.targetKey) {
                ids.insert(repositoryID)
            }
        }
        return Array(ids.prefix(maxRepositories))
    }

    private static func loadProfile(repositoryID: String,
                                    database: IntelligenceDatabase) throws -> RepositoryComparisonProfile {
        guard let repository = try database.fetchRepository(id: repositoryID) else {
            throw RepositoryCompareError.missingRepository(repositoryID)
        }

        let metadata = try database.fetchMetadata(repositoryID: repositoryID)
        let cloneState = try database.fetchCloneState(repositoryID: repositoryID)
        let stackRecords = try database.fetchDetectedStackItems(repositoryID: repositoryID)
        let insight = try database.fetchLatestAIInsight(repositoryID: repositoryID)
        let score = try database.fetchLatestRepositoryScore(repositoryID: repositoryID)
        let relationships = try database.fetchGraphRelationships(repositoryID: repositoryID)
        let recommendations = try database.fetchRecommendations(repositoryID: repositoryID, limit: 8)
        let ecosystemNames = try database.fetchEcosystemClusters(types: ["ecosystem", "workflow"])
            .compactMap { cluster -> String? in
                decodeStringArray(cluster.repositoryIDsJSON).contains(repositoryID) ? cluster.name : nil
            }

        let stackItems = stackRecords.map(\.name)
        var stackByCategory: [String: [String]] = [:]
        for item in stackRecords {
            stackByCategory[item.category, default: []].append(item.name)
        }

        let stackLower = stackItems.map { $0.lowercased() }
        let hasMCP = stackLower.contains(where: { $0.contains("mcp") }) ||
            relationships.contains(where: { $0.targetLabel.localizedCaseInsensitiveContains("mcp") })
        let hasAI = stackLower.contains(where: { $0.contains("ollama") || $0.contains("openai") || $0.contains("langchain") }) ||
            (insight?.summary.localizedCaseInsensitiveContains("ai") ?? false)

        let productionReadiness: String
        if let complexity = score?.setupComplexity, complexity <= 4, (score?.localFirstScore ?? 0) >= 7 {
            productionReadiness = "Strong local-first candidate"
        } else if (score?.setupComplexity ?? 99) <= 6 {
            productionReadiness = "Reasonable for testing"
        } else {
            productionReadiness = "Higher setup overhead"
        }

        return RepositoryComparisonProfile(
            repositoryID: repositoryID,
            fullName: repository.fullName,
            description: metadata?.description,
            primaryLanguage: metadata?.primaryLanguage,
            stars: metadata?.stars,
            licenseSPDX: metadata?.licenseSPDX,
            summary: insight?.summary,
            usefulness: insight?.usefulness,
            risks: decodeStringArray(insight?.risksJSON ?? "[]"),
            classifications: decodeStringArray(insight?.classificationsJSON ?? "[]"),
            stackItems: stackItems,
            stackByCategory: stackByCategory,
            setupComplexity: score?.setupComplexity,
            localFirstScore: score?.localFirstScore,
            experimentationPriority: score?.experimentationPriority,
            ecosystemInfluence: score?.ecosystemInfluence,
            personalRelevance: score?.personalRelevance,
            ecosystemNames: ecosystemNames,
            graphCentrality: relationships.count,
            cloneStatus: cloneState?.status,
            lastAnalyzedAt: repository.lastAnalyzedAt,
            relationshipCount: relationships.count,
            recommendationCount: recommendations.count,
            hasMCP: hasMCP,
            hasAIIntegration: hasAI,
            productionReadiness: productionReadiness
        )
    }

    private static func graphOverlap(for profiles: [RepositoryComparisonProfile],
                                     database: IntelligenceDatabase) async throws -> ComparisonGraphOverlap {
        var neighborSets = [[String]]()
        var integrations: [String] = []
        var alternatives: [String] = []

        for profile in profiles {
            let neighbors = try database.fetchGraphNeighborLabels(repositoryID: profile.repositoryID)
            neighborSets.append(neighbors)
            let rels = try database.fetchGraphRelationships(repositoryID: profile.repositoryID)
            integrations.append(contentsOf: rels.filter { $0.relationshipType == "integrates_with" }.map(\.targetLabel))
            alternatives.append(contentsOf: rels.filter { $0.relationshipType == "alternative_to" }.map(\.targetLabel))
        }

        let sharedNeighbors = neighborSets.dropFirst().reduce(Set(neighborSets.first ?? [])) { $0.intersection($1) }.sorted()

        return ComparisonGraphOverlap(
            sharedNeighbors: sharedNeighbors,
            pairPaths: [],
            sharedIntegrations: Array(Set(integrations)).sorted(),
            alternativeLinks: Array(Set(alternatives)).sorted()
        )
    }

    private static func persistSession(repositoryIDs: [String],
                                       database: IntelligenceDatabase) throws {
        let now = IntelligenceDatabase.iso8601String()
        let sessionID = repositoryIDs.sorted().joined(separator: "|")
        let existing = try database.fetchComparisonSession(id: sessionID)
        let title = repositoryIDs.compactMap { try? database.fetchRepository(id: $0)?.fullName }.joined(separator: " vs ")
        let record = ComparisonSessionRecord(
            id: sessionID,
            repositoryIDsJSON: encodeStringArray(repositoryIDs),
            title: title.isEmpty ? nil : title,
            isFavorite: existing?.isFavorite ?? false,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try database.upsertComparisonSession(record)
    }

    private static func extractRepositoryID(from targetKey: String) -> String? {
        guard targetKey.hasPrefix("repository:") else { return nil }
        return String(targetKey.dropFirst("repository:".count))
    }

    private static func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func encodeResult(_ result: RepositoryComparisonResult) -> String {
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func decodeResult(_ json: String) -> RepositoryComparisonResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RepositoryComparisonResult.self, from: data)
    }

    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum RepositoryCompareError: LocalizedError {
    case invalidSelection
    case missingRepository(String)

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            return "Select between 2 and 4 repositories to compare."
        case let .missingRepository(id):
            return "Repository \(id) is no longer available."
        }
    }
}
