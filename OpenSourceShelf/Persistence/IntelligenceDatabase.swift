import Foundation
import GRDB

enum IntelligenceDatabaseError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            "The intelligence database has not been initialized."
        }
    }
}

final class IntelligenceDatabase {
    static let shared = IntelligenceDatabase()
    private static let defaultEmbeddingModel = "nomic-embed-text"
    private static let semanticIndexStateQueryHash = "__semantic_index_state__"

    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private(set) var databaseURL: URL
    private(set) var databaseQueue: DatabaseQueue?

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        let rootURL = baseDirectoryURL
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("reshelf", isDirectory: true)
        self.baseDirectoryURL = rootURL
        self.databaseURL = rootURL
            .appendingPathComponent("database", isDirectory: true)
            // Filename kept as-is (invisible, inside ~/reshelf/database/) to avoid
            // moving GRDB -wal/-shm sidecar files during the rename.
            .appendingPathComponent("opensource-shelf.sqlite", isDirectory: false)
    }

    func initialize() throws {
        if databaseQueue != nil {
            return
        }

        let databaseDirectory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try repairLegacyOrphanRows(in: queue)
        let migrator = IntelligenceMigrations.makeMigrator()
        try migrator.migrate(queue)
        databaseQueue = queue
    }

    func read<T>(_ value: (Database) throws -> T) throws -> T {
        try requireDatabaseQueue().read(value)
    }

    func write<T>(_ updates: (Database) throws -> T) throws -> T {
        try requireDatabaseQueue().write(updates)
    }

    func fetchRepository(id: String) throws -> RepositoryRecord? {
        try read { db in
            try RepositoryRecord.fetchOne(db, key: id)
        }
    }

    func fetchRepository(fullName: String) throws -> RepositoryRecord? {
        try read { db in
            try RepositoryRecord
                .filter(Column("full_name") == fullName)
                .fetchOne(db)
        }
    }

    func fetchRepository(githubURL: String) throws -> RepositoryRecord? {
        try read { db in
            try RepositoryRecord
                .filter(Column("github_url") == githubURL)
                .fetchOne(db)
        }
    }

    func fetchRepository(uniquelyByName name: String) throws -> RepositoryRecord? {
        try read { db in
            let records = try RepositoryRecord
                .filter(Column("name") == name)
                .fetchAll(db)
            guard records.count == 1 else { return nil }
            return records.first
        }
    }

    func fetchRepositories(ids: [String]) throws -> [RepositoryRecord] {
        guard !ids.isEmpty else { return [] }
        return try read { db in
            try RepositoryRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }
    }

    func fetchCloneStates(repositoryIDs: [String]) throws -> [String: CloneStateRecord] {
        guard !repositoryIDs.isEmpty else { return [:] }
        return try read { db in
            let rows = try CloneStateRecord
                .filter(repositoryIDs.contains(Column("repository_id")))
                .fetchAll(db)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0.repositoryID, $0) })
        }
    }

    func fetchLatestRunbooks(repositoryIDs: [String]) throws -> [String: RepositoryRunbookRecord] {
        guard !repositoryIDs.isEmpty else { return [:] }
        return try read { db in
            let placeholders = Array(repeating: "?", count: repositoryIDs.count).joined(separator: ", ")
            let sql = """
            SELECT r.*
            FROM repository_runbooks r
            INNER JOIN (
                SELECT repository_id, MAX(updated_at) AS max_updated
                FROM repository_runbooks
                WHERE repository_id IN (\(placeholders))
                GROUP BY repository_id
            ) latest
            ON r.repository_id = latest.repository_id AND r.updated_at = latest.max_updated
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(repositoryIDs))
            var result: [String: RepositoryRunbookRecord] = [:]
            for row in rows {
                let record = try RepositoryRunbookRecord(row: row)
                result[record.repositoryID] = record
            }
            return result
        }
    }

    func fetchActiveRunbookJobRepositoryIDs(repositoryIDs: [String]) throws -> Set<String> {
        guard !repositoryIDs.isEmpty else { return [] }
        return try read { db in
            let ids = try IngestionJobRecord
                .filter(repositoryIDs.contains(Column("repository_id")))
                .filter(Column("type") == "generate_runbook")
                .filter(["pending", "running"].contains(Column("status")))
                .fetchAll(db)
                .map(\.repositoryID)
            return Set(ids.compactMap { $0 })
        }
    }

    func fetchActiveRunbookJobs(repositoryIDs: [String]) throws -> [String: IngestionJobRecord] {
        guard !repositoryIDs.isEmpty else { return [:] }
        return try read { db in
            let jobs = try IngestionJobRecord
                .filter(repositoryIDs.contains(Column("repository_id")))
                .filter(Column("type") == "generate_runbook")
                .filter(["pending", "running"].contains(Column("status")))
                .order(Column("created_at").desc)
                .fetchAll(db)
            var result: [String: IngestionJobRecord] = [:]
            for job in jobs {
                guard let repositoryID = job.repositoryID else { continue }
                if result[repositoryID] == nil {
                    result[repositoryID] = job
                }
            }
            return result
        }
    }

    func upsert(repository: RepositoryRecord,
                metadata: RepositoryMetadataRecord? = nil,
                cloneState: CloneStateRecord? = nil,
                ingestionJob: IngestionJobRecord? = nil) throws {
        try write { db in
            try repository.upsert(db)
            if let metadata {
                try metadata.upsert(db)
            }
            if let cloneState {
                try cloneState.upsert(db)
            }
            if let ingestionJob {
                try ingestionJob.upsert(db)
            }
        }
    }

    func upsert(ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try ingestionJob.upsert(db)
        }
    }

    func replaceStaticAnalysis(repositoryID: String,
                               files: [RepositoryFileRecord],
                               manifests: [RepositoryManifestRecord],
                               stackItems: [DetectedStackItemRecord],
                               ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try RepositoryFileRecord
                .filter(Column("repository_id") == repositoryID)
                .deleteAll(db)
            try RepositoryManifestRecord
                .filter(Column("repository_id") == repositoryID)
                .deleteAll(db)
            try DetectedStackItemRecord
                .filter(Column("repository_id") == repositoryID)
                .deleteAll(db)

            for file in files {
                try file.insert(db)
            }
            for manifest in manifests {
                try manifest.insert(db)
            }
            for stackItem in stackItems {
                try stackItem.insert(db)
            }
            try ingestionJob.upsert(db)
        }
    }

    func upsert(aiInsight: AIInsightRecord,
                repositoryScore: RepositoryScoreRecord,
                ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try aiInsight.upsert(db)
            try repositoryScore.upsert(db)
            try ingestionJob.upsert(db)
        }
    }

    func upsertGraph(repositoryID: String,
                     nodes: [GraphNode],
                     edges: [GraphEdge],
                     ingestionJob: IngestionJobRecord) throws {
        try write { db in
            for node in nodes {
                try node.upsert(db)
            }
            try deleteOutgoingGraphEdges(repositoryID: repositoryID, db: db)
            for edge in edges {
                try upsertGraphEdge(edge, db: db)
            }
            try ingestionJob.upsert(db)
        }
    }

    func replaceRecommendations(repositoryID: String,
                                cacheKey: String,
                                recommendations: [RepositoryRecommendationRecord],
                                ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try RepositoryRecommendationRecord
                .filter(Column("source_repository_id") == repositoryID)
                .deleteAll(db)
            for recommendation in recommendations {
                try recommendation.upsert(db)
            }
            try ingestionJob.upsert(db)
        }
    }

    func replaceEcosystemClusters(cacheKey: String,
                                  clusters: [EcosystemClusterRecord],
                                  ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try EcosystemClusterRecord.deleteAll(db)
            for cluster in clusters {
                try cluster.upsert(db)
            }
            try ingestionJob.upsert(db)
        }
    }

    func replaceExplorationIndex(cacheKey: String,
                                 entries: [ExplorationIndexEntryRecord],
                                 ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try ExplorationIndexEntryRecord.deleteAll(db)
            for entry in entries {
                try entry.upsert(db)
            }
            try ingestionJob.upsert(db)
        }
    }

    func fetchMetadata(repositoryID: String) throws -> RepositoryMetadataRecord? {
        try read { db in
            try RepositoryMetadataRecord.fetchOne(db, key: repositoryID)
        }
    }

    func fetchCloneState(repositoryID: String) throws -> CloneStateRecord? {
        try read { db in
            try CloneStateRecord.fetchOne(db, key: repositoryID)
        }
    }

    func fetchDetectedStackItems(repositoryID: String) throws -> [DetectedStackItemRecord] {
        try read { db in
            try DetectedStackItemRecord
                .filter(Column("repository_id") == repositoryID)
                .order(Column("category"), Column("confidence").desc, Column("name"))
                .fetchAll(db)
        }
    }

    func fetchRepositoryManifests(repositoryID: String) throws -> [RepositoryManifestRecord] {
        try read { db in
            try RepositoryManifestRecord
                .filter(Column("repository_id") == repositoryID)
                .order(Column("ecosystem"), Column("path"))
                .fetchAll(db)
        }
    }

    func fetchAIInsight(cacheKey: String) throws -> AIInsightRecord? {
        try read { db in
            try AIInsightRecord
                .filter(Column("cache_key") == cacheKey)
                .fetchOne(db)
        }
    }

    func fetchLatestAIInsight(repositoryID: String) throws -> AIInsightRecord? {
        try read { db in
            try AIInsightRecord
                .filter(Column("repository_id") == repositoryID)
                .order(Column("generated_at").desc)
                .fetchOne(db)
        }
    }

    func fetchRepositoryScore(cacheKey: String) throws -> RepositoryScoreRecord? {
        try read { db in
            try RepositoryScoreRecord
                .filter(Column("cache_key") == cacheKey)
                .fetchOne(db)
        }
    }

    func fetchLatestRepositoryScore(repositoryID: String) throws -> RepositoryScoreRecord? {
        try read { db in
            try RepositoryScoreRecord
                .filter(Column("repository_id") == repositoryID)
                .order(Column("generated_at").desc)
                .fetchOne(db)
        }
    }

    func fetchGraphRelationships(repositoryID: String,
                                 relationshipTypes: [String]? = nil,
                                 targetTypes: [String]? = nil) throws -> [GraphRelationshipSummary] {
        try read { db in
            let repositoryKey = "repository:\(repositoryID)"
            let relationshipSQL: String
            var arguments: StatementArguments = [repositoryKey]

            if let relationshipTypes, !relationshipTypes.isEmpty {
                relationshipSQL = "AND e.relationship_type IN (\(relationshipTypes.map { _ in "?" }.joined(separator: ",")))"
                for type in relationshipTypes {
                    arguments += [type]
                }
            } else {
                relationshipSQL = ""
            }

            let targetSQL: String
            if let targetTypes, !targetTypes.isEmpty {
                targetSQL = "AND target.type IN (\(targetTypes.map { _ in "?" }.joined(separator: ",")))"
                for type in targetTypes {
                    arguments += [type]
                }
            } else {
                targetSQL = ""
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    e.id,
                    e.relationship_type,
                    e.confidence,
                    e.evidence_text,
                    e.evidence_path,
                    e.created_by,
                    target.type AS target_type,
                    target.key AS target_key,
                    target.label AS target_label
                FROM graph_edges e
                JOIN graph_nodes source ON source.id = e.source_node_id
                JOIN graph_nodes target ON target.id = e.target_node_id
                WHERE source.key = ?
                \(relationshipSQL)
                \(targetSQL)
                ORDER BY e.confidence DESC, e.relationship_type, target.label
                """,
                arguments: arguments
            )
            return rows.map(GraphRelationshipSummary.init(row:))
        }
    }

    func fetchRelatedRepositories(repositoryID: String) throws -> [GraphRelationshipSummary] {
        try fetchGraphRelationships(repositoryID: repositoryID, targetTypes: ["repository"])
    }

    func fetchAlternatives(repositoryID: String) throws -> [GraphRelationshipSummary] {
        try fetchGraphRelationships(repositoryID: repositoryID, relationshipTypes: ["alternative_to"])
    }

    func fetchIntegrations(repositoryID: String) throws -> [GraphRelationshipSummary] {
        try fetchGraphRelationships(repositoryID: repositoryID, relationshipTypes: ["integrates_with", "compatible_with"])
    }

    func fetchSameEcosystem(repositoryID: String) throws -> [GraphRelationshipSummary] {
        try fetchGraphRelationships(repositoryID: repositoryID, relationshipTypes: ["same_stack", "same_problem_space"])
    }

    func fetchRepositoriesSharingStack(repositoryID: String) throws -> [GraphRelationshipSummary] {
        try read { db in
            let repositoryKey = "repository:\(repositoryID)"
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT
                    other_edge.id,
                    other_edge.relationship_type,
                    other_edge.confidence,
                    other_edge.evidence_text,
                    other_edge.evidence_path,
                    other_edge.created_by,
                    other_repo.type AS target_type,
                    other_repo.key AS target_key,
                    other_repo.label AS target_label
                FROM graph_edges stack_edge
                JOIN graph_nodes source_repo ON source_repo.id = stack_edge.source_node_id
                JOIN graph_edges other_edge ON other_edge.target_node_id = stack_edge.target_node_id
                JOIN graph_nodes other_repo ON other_repo.id = other_edge.source_node_id
                WHERE source_repo.key = ?
                  AND source_repo.id != other_repo.id
                  AND source_repo.type = 'repository'
                  AND other_repo.type = 'repository'
                  AND stack_edge.relationship_type = 'same_stack'
                  AND other_edge.relationship_type = 'same_stack'
                ORDER BY other_edge.confidence DESC, other_repo.label
                """,
                arguments: [repositoryKey]
            )
            return rows.map(GraphRelationshipSummary.init(row:))
        }
    }

    func fetchGraphNode(key: String) throws -> GraphNode? {
        try read { db in
            try GraphNode
                .filter(Column("key") == key)
                .fetchOne(db)
        }
    }

    func fetchGraphNodes(ids: [String]) throws -> [GraphNode] {
        guard !ids.isEmpty else { return [] }
        return try read { db in
            try GraphNode
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }
    }

    func fetchGraphEdges(forNodeIDs nodeIDs: Set<String>) throws -> [GraphEdge] {
        guard !nodeIDs.isEmpty else { return [] }
        let ids = Array(nodeIDs)
        return try read { db in
            try GraphEdge
                .filter(ids.contains(Column("source_node_id")) || ids.contains(Column("target_node_id")))
                .fetchAll(db)
        }
    }

    func fetchOutgoingGraphEdges(sourceNodeID: String,
                                 relationshipTypes: [String]? = nil,
                                 minConfidence: Double = 0) throws -> [GraphEdge] {
        try read { db in
            var sql = """
            SELECT *
            FROM graph_edges
            WHERE source_node_id = ?
              AND confidence >= ?
            """
            var arguments: StatementArguments = [sourceNodeID, minConfidence]
            if let relationshipTypes, !relationshipTypes.isEmpty {
                sql += " AND relationship_type IN (\(relationshipTypes.map { _ in "?" }.joined(separator: ",")))"
                for type in relationshipTypes {
                    arguments += [type]
                }
            }
            sql += " ORDER BY confidence DESC"
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.map { row in
                GraphEdge(
                    id: row["id"],
                    sourceNodeID: row["source_node_id"],
                    targetNodeID: row["target_node_id"],
                    relationshipType: row["relationship_type"],
                    confidence: row["confidence"],
                    evidenceText: row["evidence_text"],
                    evidencePath: row["evidence_path"],
                    createdBy: row["created_by"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    func fetchGraphNeighborhood(repositoryID: String,
                              filters: GraphFilterState,
                              maxNodes: Int,
                              maxEdges: Int) throws -> GraphNeighborhood {
        let repositoryKey = "repository:\(repositoryID)"
        guard let focusNode = try fetchGraphNode(key: repositoryKey) else {
            return GraphNeighborhood(focusRepositoryID: repositoryID, nodes: [], edges: [], ecosystemNames: [])
        }

        let relationshipTypes = filters.enabledRelationshipTypes.isEmpty
            ? GraphFilterState.defaultRelationshipTypes
            : Array(filters.enabledRelationshipTypes)

        var edgesByID: [String: GraphEdge] = [:]
        var nodeIDs: Set<String> = [focusNode.id]

        let hopOne = try fetchOutgoingGraphEdges(sourceNodeID: focusNode.id,
                                                 relationshipTypes: relationshipTypes,
                                                 minConfidence: filters.minConfidence)
        for edge in hopOne.prefix(maxEdges) {
            edgesByID[edge.id] = edge
            nodeIDs.insert(edge.targetNodeID)
        }

        if filters.includeSecondHop {
            let repoTargets = try fetchGraphNodes(ids: Array(nodeIDs))
                .filter { $0.type == "repository" && $0.id != focusNode.id }
                .prefix(6)
            for repoNode in repoTargets {
                let hopTwo = try fetchOutgoingGraphEdges(sourceNodeID: repoNode.id,
                                                         relationshipTypes: relationshipTypes,
                                                         minConfidence: filters.minConfidence)
                for edge in hopTwo.prefix(8) {
                    edgesByID[edge.id] = edge
                    nodeIDs.insert(edge.targetNodeID)
                    if edgesByID.count >= maxEdges { break }
                }
                if edgesByID.count >= maxEdges { break }
            }

            for summary in try fetchRepositoriesSharingStack(repositoryID: repositoryID).prefix(6) {
                if let repoNode = try fetchGraphNode(key: summary.targetKey) {
                    nodeIDs.insert(repoNode.id)
                }
            }
        }

        let fetchedNodes = Array(try fetchGraphNodes(ids: Array(nodeIDs)).prefix(maxNodes))
        let nodes = filterGraphNodes(fetchedNodes, repositoryID: repositoryID, filters: filters)
        let visibleNodeIDs = Set(nodes.map(\.id))
        let edges = Array(edgesByID.values)
            .filter { visibleNodeIDs.contains($0.sourceNodeID) && visibleNodeIDs.contains($0.targetNodeID) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxEdges)

        let ecosystemNames = try fetchEcosystemNames(forRepositoryID: repositoryID, filters: filters)

        return GraphNeighborhood(
            focusRepositoryID: repositoryID,
            nodes: nodes,
            edges: Array(edges),
            ecosystemNames: ecosystemNames
        )
    }

    func fetchGraphFocusCandidates(limit: Int) throws -> [GraphFocusCandidate] {
        try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    r.id,
                    r.full_name,
                    COUNT(e.id) AS relationship_count
                FROM repositories r
                LEFT JOIN graph_nodes n ON n.key = 'repository:' || r.id
                LEFT JOIN graph_edges e ON e.source_node_id = n.id
                GROUP BY r.id, r.full_name
                ORDER BY relationship_count DESC, r.full_name
                LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map { row in
                GraphFocusCandidate(id: row["id"],
                                    fullName: row["full_name"],
                                    relationshipCount: row["relationship_count"] ?? 0)
            }
        }
    }

    func fetchGraphLayoutCache(focusRepositoryID: String) throws -> GraphLayoutCacheRecord? {
        try read { db in
            try GraphLayoutCacheRecord.fetchOne(db, key: focusRepositoryID)
        }
    }

    func upsertGraphLayoutCache(_ record: GraphLayoutCacheRecord) throws {
        try write { db in
            try record.upsert(db)
        }
    }

    func deleteGraphLayoutCache(focusRepositoryID: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM graph_layout_cache WHERE focus_repository_id = ?",
                           arguments: [focusRepositoryID])
        }
    }

    func clearGraphLayoutCache() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM graph_layout_cache")
        }
    }

    func searchGraphNodes(query: String, limit: Int) throws -> [GraphNode] {
        let pattern = "%\(query)%"
        return try read { db in
            try GraphNode.fetchAll(
                db,
                sql: """
                SELECT *
                FROM graph_nodes
                WHERE label LIKE ? COLLATE NOCASE
                   OR key LIKE ? COLLATE NOCASE
                   OR type LIKE ? COLLATE NOCASE
                ORDER BY
                    CASE WHEN label LIKE ? COLLATE NOCASE THEN 0 ELSE 1 END,
                    label
                LIMIT ?
                """,
                arguments: [pattern, pattern, pattern, pattern, limit]
            )
        }
    }

    func searchGraphRepositories(query: String, limit: Int) throws -> [RepositoryRecord] {
        let pattern = "%\(query)%"
        return try read { db in
            try RepositoryRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM repositories
                WHERE full_name LIKE ? COLLATE NOCASE
                   OR name LIKE ? COLLATE NOCASE
                ORDER BY full_name
                LIMIT ?
                """,
                arguments: [pattern, pattern, limit]
            )
        }
    }

    func searchEcosystemClusters(query: String, limit: Int) throws -> [EcosystemClusterSummary] {
        let pattern = "%\(query)%"
        return try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    id,
                    cluster_type,
                    name,
                    score,
                    confidence,
                    repository_ids_json,
                    repository_names_json,
                    common_stack_json,
                    strongest_tools_json,
                    integrations_json,
                    recommendation_highlights_json,
                    missing_pieces_json,
                    signals_json,
                    explanation,
                    cache_key,
                    generated_at
                FROM ecosystem_clusters
                WHERE name LIKE ? COLLATE NOCASE
                   OR explanation LIKE ? COLLATE NOCASE
                ORDER BY score DESC, name
                LIMIT ?
                """,
                arguments: [pattern, pattern, limit]
            )
            return rows.map(EcosystemClusterSummary.init(row:))
        }
    }

    func fetchIncomingGraphEdges(targetNodeID: String,
                                 relationshipTypes: [String]? = nil,
                                 minConfidence: Double = 0,
                                 limit: Int = 12) throws -> [GraphEdge] {
        try read { db in
            var sql = """
            SELECT *
            FROM graph_edges
            WHERE target_node_id = ?
              AND confidence >= ?
            """
            var arguments: StatementArguments = [targetNodeID, minConfidence]
            if let relationshipTypes, !relationshipTypes.isEmpty {
                sql += " AND relationship_type IN (\(relationshipTypes.map { _ in "?" }.joined(separator: ",")))"
                for type in relationshipTypes {
                    arguments += [type]
                }
            }
            sql += " ORDER BY confidence DESC LIMIT ?"
            arguments += [limit]
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.map(graphEdge(from:))
        }
    }

    func fetchAdjacentGraphEdges(nodeID: String,
                                 minConfidence: Double,
                                 limit: Int) throws -> [GraphEdge] {
        try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT *
                FROM graph_edges
                WHERE (source_node_id = ? OR target_node_id = ?)
                  AND confidence >= ?
                ORDER BY confidence DESC
                LIMIT ?
                """,
                arguments: [nodeID, nodeID, minConfidence, limit]
            )
            return rows.map(graphEdge(from:))
        }
    }

    func fetchGraphPathCache(cacheKey: String) throws -> GraphPathCacheRecord? {
        try read { db in
            try GraphPathCacheRecord.fetchOne(db, key: cacheKey)
        }
    }

    func upsertGraphPathCache(_ record: GraphPathCacheRecord) throws {
        try write { db in
            try record.upsert(db)
        }
    }

    func clearGraphPathCache() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM graph_path_cache")
        }
    }

    func fetchGraphNavigationCache() throws -> GraphNavigationSnapshot? {
        try read { db in
            guard let record = try GraphNavigationCacheRecord.fetchOne(db, key: "default"),
                  let data = record.payloadJSON.data(using: .utf8) else {
                return nil
            }
            return try JSONDecoder().decode(GraphNavigationSnapshot.self, from: data)
        }
    }

    func upsertGraphNavigationCache(_ record: GraphNavigationCacheRecord) throws {
        try write { db in
            try record.upsert(db)
        }
    }

    func clearGraphNavigationCache() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM graph_navigation_cache")
        }
    }

    func fetchComparisonResultsCache(cacheSignature: String) throws -> ComparisonResultsCacheRecord? {
        try read { db in
            try ComparisonResultsCacheRecord.fetchOne(db, key: cacheSignature)
        }
    }

    func upsertComparisonResultsCache(_ record: ComparisonResultsCacheRecord) throws {
        try write { db in
            try record.upsert(db)
        }
    }

    func fetchRecentComparisonSessions(limit: Int = 12) throws -> [ComparisonSessionRecord] {
        try read { db in
            try ComparisonSessionRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM comparison_sessions
                ORDER BY updated_at DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    func fetchFavoriteComparisonSessions(limit: Int = 24) throws -> [ComparisonSessionRecord] {
        try read { db in
            try ComparisonSessionRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM comparison_sessions
                WHERE is_favorite = 1
                ORDER BY updated_at DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }
    }

    func fetchComparisonSession(id: String) throws -> ComparisonSessionRecord? {
        try read { db in
            try ComparisonSessionRecord.fetchOne(db, key: id)
        }
    }

    func setComparisonSessionFavorite(id: String, isFavorite: Bool) throws {
        let now = Self.iso8601String()
        try write { db in
            try db.execute(
                sql: """
                UPDATE comparison_sessions
                SET is_favorite = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [isFavorite, now, id]
            )
        }
    }

    func upsertComparisonSession(_ record: ComparisonSessionRecord) throws {
        try write { db in
            try record.upsert(db)
        }
    }

    func deleteComparisonSession(id: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM comparison_sessions WHERE id = ?", arguments: [id])
        }
    }

    func fetchCompareFocusCandidates(limit: Int = 200) throws -> [CompareFocusCandidate] {
        try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    r.id,
                    r.full_name,
                    COUNT(e.id) AS relationship_count
                FROM repositories r
                LEFT JOIN graph_nodes n ON n.key = 'repository:' || r.id
                LEFT JOIN graph_edges e ON e.source_node_id = n.id
                GROUP BY r.id, r.full_name
                ORDER BY r.full_name
                LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map { row in
                CompareFocusCandidate(id: row["id"],
                                      fullName: row["full_name"],
                                      relationshipCount: row["relationship_count"] ?? 0)
            }
        }
    }

    func searchCompareRepositories(query: String, limit: Int = 20) throws -> [RepositoryRecord] {
        let pattern = "%\(query)%"
        return try read { db in
            try RepositoryRecord.fetchAll(
                db,
                sql: """
                SELECT *
                FROM repositories
                WHERE full_name LIKE ? COLLATE NOCASE
                   OR name LIKE ? COLLATE NOCASE
                ORDER BY full_name
                LIMIT ?
                """,
                arguments: [pattern, pattern, limit]
            )
        }
    }

    func fetchGraphNeighborLabels(repositoryID: String, limit: Int = 12) throws -> [String] {
        guard let node = try fetchGraphNode(key: "repository:\(repositoryID)") else { return [] }
        let edges = try fetchAdjacentGraphEdges(nodeID: node.id, minConfidence: 0.35, limit: limit)
        var labels: [String] = []
        for edge in edges {
            let peerID = edge.sourceNodeID == node.id ? edge.targetNodeID : edge.sourceNodeID
            if let peer = try fetchGraphNodes(ids: [peerID]).first {
                labels.append(peer.label)
            }
        }
        return Array(Set(labels)).sorted()
    }

    func comparisonEvidenceSignature(repositoryIDs: [String]) throws -> String {
        let sorted = repositoryIDs.sorted()
        var parts: [String] = sorted
        for repositoryID in sorted {
            if let score = try fetchLatestRepositoryScore(repositoryID: repositoryID) {
                parts.append("score:\(repositoryID):\(score.generatedAt)")
            }
            if let insight = try fetchLatestAIInsight(repositoryID: repositoryID) {
                parts.append("ai:\(repositoryID):\(insight.cacheKey):\(insight.generatedAt)")
            }
            let stack = try fetchDetectedStackItems(repositoryID: repositoryID)
            if let latest = stack.map(\.detectedAt).max() {
                parts.append("stack:\(repositoryID):\(latest)")
            }
            let relationships = try fetchGraphRelationships(repositoryID: repositoryID)
            parts.append("graph:\(repositoryID):\(relationships.count)")
        }
        return parts.joined(separator: "|")
    }

    private func graphEdge(from row: Row) -> GraphEdge {
        GraphEdge(
            id: row["id"],
            sourceNodeID: row["source_node_id"],
            targetNodeID: row["target_node_id"],
            relationshipType: row["relationship_type"],
            confidence: row["confidence"],
            evidenceText: row["evidence_text"],
            evidencePath: row["evidence_path"],
            createdBy: row["created_by"],
            createdAt: row["created_at"]
        )
    }

    private func fetchEcosystemNames(forRepositoryID repositoryID: String,
                                     filters: GraphFilterState) throws -> [String] {
        let clusters = try fetchEcosystemClusters(types: ["ecosystem", "workflow"])
        return clusters.compactMap { cluster in
            guard decodeStringArray(cluster.repositoryIDsJSON).contains(repositoryID) else { return nil }
            if let filter = filters.ecosystemName, filter != cluster.name { return nil }
            return cluster.name
        }
    }

    private func filterGraphNodes(_ nodes: [GraphNode],
                                repositoryID: String,
                                filters: GraphFilterState) -> [GraphNode] {
        guard filters.localFirstOnly || filters.mcpCompatibleOnly || filters.clonedOnly
                || filters.aiToolingOnly || filters.desktopToolingOnly else {
            return nodes
        }

        return nodes.filter { node in
            if node.type == "repository" {
                let repoID = node.key.replacingOccurrences(of: "repository:", with: "")
                guard passesRepositoryFilters(repositoryID: repoID, filters: filters) else { return false }
            }
            if filters.aiToolingOnly && node.type == "ai_tool" { return true }
            if filters.desktopToolingOnly && ["framework", "runtime"].contains(node.type) {
                let label = node.label.lowercased()
                return label.contains("swift") || label.contains("macos") || label.contains("tauri") || label.contains("electron")
            }
            return !filters.aiToolingOnly && !filters.desktopToolingOnly
        }
    }

    private func passesRepositoryFilters(repositoryID: String, filters: GraphFilterState) -> Bool {
        do {
            let metadata = try fetchMetadata(repositoryID: repositoryID)
            let clone = try fetchCloneState(repositoryID: repositoryID)
            let stack = try fetchDetectedStackItems(repositoryID: repositoryID)
            let topics = decodeStringArray(metadata?.topicsJSON ?? "[]").map { $0.lowercased() }
            let stackLabels = stack.map { $0.name.lowercased() }.joined(separator: " ")

            if filters.clonedOnly && clone?.status != "cloned" { return false }
            if filters.localFirstOnly {
                let localSignals = topics + [stackLabels, metadata?.description?.lowercased() ?? ""]
                let joined = localSignals.joined(separator: " ")
                if !joined.contains("local") && !joined.contains("self-hosted") && !joined.contains("offline") {
                    return false
                }
            }
            if filters.mcpCompatibleOnly {
                let joined = (topics + [stackLabels]).joined(separator: " ")
                if !joined.contains("mcp") { return false }
            }
            if filters.aiToolingOnly {
                let joined = (topics + [stackLabels, metadata?.description?.lowercased() ?? ""]).joined(separator: " ")
                if !joined.contains("ai") && !joined.contains("llm") && !joined.contains("ollama") {
                    return false
                }
            }
            if filters.desktopToolingOnly {
                let joined = (topics + [stackLabels]).joined(separator: " ")
                if !joined.contains("macos") && !joined.contains("swift") && !joined.contains("tauri") && !joined.contains("electron") {
                    return false
                }
            }
            return true
        } catch {
            return true
        }
    }

    private func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    func fetchGraphRecommendationSignals(repositoryID: String) throws -> [GraphRecommendationSignal] {
        try read { db in
            let repositoryKey = "repository:\(repositoryID)"
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    e.id,
                    e.target_node_id,
                    e.relationship_type,
                    e.confidence,
                    e.evidence_text,
                    e.evidence_path,
                    e.created_by,
                    target.type AS target_type,
                    target.key AS target_key,
                    target.label AS target_label
                FROM graph_edges e
                JOIN graph_nodes source ON source.id = e.source_node_id
                JOIN graph_nodes target ON target.id = e.target_node_id
                WHERE source.key = ?
                ORDER BY e.confidence DESC, e.relationship_type, target.label
                """,
                arguments: [repositoryKey]
            )
            let stackOverlapRows = try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT
                    other_repo.id || ':' || stack_node.id AS id,
                    other_repo.id AS target_node_id,
                    'same_stack' AS relationship_type,
                    MIN(1.0, (stack_edge.confidence + other_edge.confidence) / 2.0) AS confidence,
                    'Shares stack evidence: ' || stack_node.label AS evidence_text,
                    other_edge.evidence_path AS evidence_path,
                    'deterministic_stack_overlap' AS created_by,
                    other_repo.type AS target_type,
                    other_repo.key AS target_key,
                    other_repo.label AS target_label
                FROM graph_edges stack_edge
                JOIN graph_nodes source_repo ON source_repo.id = stack_edge.source_node_id
                JOIN graph_nodes stack_node ON stack_node.id = stack_edge.target_node_id
                JOIN graph_edges other_edge ON other_edge.target_node_id = stack_edge.target_node_id
                JOIN graph_nodes other_repo ON other_repo.id = other_edge.source_node_id
                WHERE source_repo.key = ?
                  AND source_repo.id != other_repo.id
                  AND source_repo.type = 'repository'
                  AND other_repo.type = 'repository'
                  AND stack_edge.relationship_type IN ('same_stack', 'implements_protocol', 'useful_for')
                  AND other_edge.relationship_type IN ('same_stack', 'implements_protocol', 'useful_for')
                ORDER BY confidence DESC, other_repo.label
                """,
                arguments: [repositoryKey]
            )
            return (rows + stackOverlapRows).map(GraphRecommendationSignal.init(row:))
        }
    }

    func fetchRecommendationCacheKey(repositoryID: String) throws -> String {
        try read { db in
            let graphSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(edge_signature, '|'), 'no-graph')
                FROM (
                    SELECT source.key || '>' || target.key || ':' || e.relationship_type || ':' || e.confidence || ':' ||
                           COALESCE(e.evidence_path, '') || ':' || COALESCE(e.evidence_text, '') || ':' || e.created_by
                           AS edge_signature
                    FROM graph_edges e
                    JOIN graph_nodes source ON source.id = e.source_node_id
                    JOIN graph_nodes target ON target.id = e.target_node_id
                    ORDER BY edge_signature
                )
                """
            ) ?? "no-graph"
            let insightTimestamp = try String.fetchOne(
                db,
                sql: "SELECT MAX(generated_at) FROM ai_insights WHERE repository_id = ?",
                arguments: [repositoryID]
            ) ?? "no-ai"
            let scoreSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(score_signature, '|'), 'no-score')
                FROM (
                    SELECT repository_id || ':' || setup_complexity || ':' || local_first_score || ':' ||
                           experimentation_priority || ':' || ecosystem_influence || ':' || personal_relevance || ':' ||
                           generated_at AS score_signature
                    FROM repository_scores
                    ORDER BY score_signature
                )
                """
            ) ?? "no-score"
            let stackSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(stack_signature, '|'), 'no-stack')
                FROM (
                    SELECT repository_id || ':' || name || ':' || category || ':' || detection_source || ':' ||
                           confidence || ':' || COALESCE(evidence_path, '') || ':' || COALESCE(evidence_text, '') || ':' ||
                           detected_at AS stack_signature
                    FROM detected_stack_items
                    ORDER BY stack_signature
                )
                """
            ) ?? "no-stack"
            let cloneSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(clone_signature, '|'), 'no-clone')
                FROM (
                    SELECT repository_id || ':' || status || ':' || clone_mode || ':' ||
                           COALESCE(path, '') || ':' || COALESCE(current_head, '') || ':' ||
                           COALESCE(last_fetch_at, '') AS clone_signature
                    FROM clone_states
                    ORDER BY clone_signature
                )
                """
            ) ?? "no-clone"
            return [repositoryID, graphSignature, insightTimestamp, scoreSignature, stackSignature, cloneSignature]
                .joined(separator: "|")
        }
    }

    func hasRecommendations(repositoryID: String, cacheKey: String) throws -> Bool {
        try read { db in
            let count = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM repository_recommendations
                WHERE source_repository_id = ?
                  AND cache_key = ?
                """,
                arguments: [repositoryID, cacheKey]
            ) ?? 0
            return count > 0
        }
    }

    func fetchRecommendations(repositoryID: String,
                              types: [String]? = nil,
                              limit: Int = 12) throws -> [RepositoryRecommendationSummary] {
        try read { db in
            let typeSQL: String
            var arguments: StatementArguments = [repositoryID]
            if let types, !types.isEmpty {
                typeSQL = "AND r.recommendation_type IN (\(types.map { _ in "?" }.joined(separator: ",")))"
                for type in types {
                    arguments += [type]
                }
            } else {
                typeSQL = ""
            }
            arguments += [limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    r.id,
                    r.source_repository_id,
                    r.target_node_id,
                    r.target_repository_id,
                    r.recommendation_type,
                    r.score,
                    r.explanation,
                    r.signals_json,
                    r.generated_at,
                    target.type AS target_type,
                    target.key AS target_key,
                    target.label AS target_label
                FROM repository_recommendations r
                JOIN graph_nodes target ON target.id = r.target_node_id
                WHERE r.source_repository_id = ?
                \(typeSQL)
                ORDER BY r.score DESC, target.label
                LIMIT ?
                """,
                arguments: arguments
            )
            return rows.map(RepositoryRecommendationSummary.init(row:))
        }
    }

    func recommendRelatedRepositories(for repositoryID: String) throws -> [RepositoryRecommendationSummary] {
        try fetchRecommendations(repositoryID: repositoryID, types: ["related_repo", "same_ecosystem"])
    }

    func recommendAlternatives(for repositoryID: String) throws -> [RepositoryRecommendationSummary] {
        try fetchRecommendations(repositoryID: repositoryID, types: ["alternative"])
    }

    func recommendComplementaryTools(for repositoryID: String) throws -> [RepositoryRecommendationSummary] {
        try fetchRecommendations(repositoryID: repositoryID, types: ["complementary_tool", "pairs_well_with"])
    }

    func recommendForWorkflow(_ workflow: String) throws -> [RepositoryRecommendationSummary] {
        try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    r.id,
                    r.source_repository_id,
                    r.target_node_id,
                    r.target_repository_id,
                    r.recommendation_type,
                    r.score,
                    r.explanation,
                    r.signals_json,
                    r.generated_at,
                    target.type AS target_type,
                    target.key AS target_key,
                    target.label AS target_label
                FROM repository_recommendations r
                JOIN graph_nodes target ON target.id = r.target_node_id
                WHERE r.recommendation_type = 'same_workflow'
                  AND lower(r.explanation || ' ' || r.signals_json) LIKE ?
                ORDER BY r.score DESC, target.label
                LIMIT 20
                """,
                arguments: ["%\(workflow.lowercased())%"]
            )
            return rows.map(RepositoryRecommendationSummary.init(row:))
        }
    }

    func recommendForLocalAI() throws -> [RepositoryRecommendationSummary] {
        try recommendForWorkflow("local ai")
    }

    func fetchEcosystemCacheKey() throws -> String {
        try read { db in
            let repositorySignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(repository_signature, '|'), 'no-repositories')
                FROM (
                    SELECT id || ':' || full_name || ':' || name || ':' || github_url || ':' ||
                           COALESCE(updated_at, '') AS repository_signature
                    FROM repositories
                    ORDER BY repository_signature
                )
                """
            ) ?? "no-repositories"
            let graphSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(edge_signature, '|'), 'no-graph')
                FROM (
                    SELECT source.key || '>' || target.key || ':' || e.relationship_type || ':' || e.confidence || ':' ||
                           COALESCE(e.evidence_path, '') || ':' || COALESCE(e.evidence_text, '') || ':' || e.created_by
                           AS edge_signature
                    FROM graph_edges e
                    JOIN graph_nodes source ON source.id = e.source_node_id
                    JOIN graph_nodes target ON target.id = e.target_node_id
                    ORDER BY edge_signature
                )
                """
            ) ?? "no-graph"
            let recommendationSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(recommendation_signature, '|'), 'no-recommendations')
                FROM (
                    SELECT source_repository_id || ':' || target_node_id || ':' || recommendation_type || ':' ||
                           score || ':' || explanation || ':' || signals_json AS recommendation_signature
                    FROM repository_recommendations
                    ORDER BY recommendation_signature
                )
                """
            ) ?? "no-recommendations"
            let stackSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(stack_signature, '|'), 'no-stack')
                FROM (
                    SELECT repository_id || ':' || name || ':' || category || ':' || detection_source || ':' ||
                           confidence || ':' || COALESCE(evidence_path, '') || ':' || COALESCE(evidence_text, '') || ':' ||
                           detected_at AS stack_signature
                    FROM detected_stack_items
                    ORDER BY stack_signature
                )
                """
            ) ?? "no-stack"
            let scoreSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(score_signature, '|'), 'no-score')
                FROM (
                    SELECT repository_id || ':' || setup_complexity || ':' || local_first_score || ':' ||
                           experimentation_priority || ':' || ecosystem_influence || ':' || personal_relevance || ':' ||
                           generated_at AS score_signature
                    FROM repository_scores
                    ORDER BY score_signature
                )
                """
            ) ?? "no-score"
            let insightSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(insight_signature, '|'), 'no-insights')
                FROM (
                    SELECT repository_id || ':' || classifications_json || ':' || relationship_hints_json || ':' || generated_at
                           AS insight_signature
                    FROM ai_insights
                    ORDER BY insight_signature
                )
                """
            ) ?? "no-insights"
            return [repositorySignature, graphSignature, recommendationSignature, stackSignature, scoreSignature, insightSignature]
                .joined(separator: "|")
        }
    }

    func hasEcosystemClusters(cacheKey: String) throws -> Bool {
        try read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ecosystem_clusters WHERE cache_key = ?",
                arguments: [cacheKey]
            ) ?? 0
            return count > 0
        }
    }

    func fetchEcosystemClusters(types: [String]? = nil, limit: Int = 24) throws -> [EcosystemClusterSummary] {
        try read { db in
            let typeSQL: String
            var arguments: StatementArguments = []
            if let types, !types.isEmpty {
                typeSQL = "WHERE cluster_type IN (\(types.map { _ in "?" }.joined(separator: ",")))"
                for type in types {
                    arguments += [type]
                }
            } else {
                typeSQL = ""
            }
            arguments += [limit]

            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    id,
                    cluster_type,
                    name,
                    score,
                    confidence,
                    repository_ids_json,
                    repository_names_json,
                    common_stack_json,
                    strongest_tools_json,
                    integrations_json,
                    recommendation_highlights_json,
                    missing_pieces_json,
                    signals_json,
                    explanation,
                    generated_at
                FROM ecosystem_clusters
                \(typeSQL)
                ORDER BY score DESC, confidence DESC, name
                LIMIT ?
                """,
                arguments: arguments
            )
            return rows.map(EcosystemClusterSummary.init(row:))
        }
    }

    func fetchExplorationCacheKey() throws -> String {
        try read { db in
            let repositorySignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(repository_signature, '|'), 'no-repositories')
                FROM (
                    SELECT r.id || ':' || r.full_name || ':' || r.name || ':' || r.github_url || ':' ||
                           COALESCE(r.updated_at, '') || ':' || COALESCE(m.description, '') || ':' ||
                           COALESCE(m.primary_language, '') AS repository_signature
                    FROM repositories r
                    LEFT JOIN repository_metadata m ON m.repository_id = r.id
                    ORDER BY repository_signature
                )
                """
            ) ?? "no-repositories"
            let ecosystemSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(cluster_signature, '|'), 'no-clusters')
                FROM (
                    SELECT cluster_type || ':' || name || ':' || score || ':' || confidence || ':' ||
                           repository_ids_json || ':' || common_stack_json || ':' || missing_pieces_json || ':' ||
                           signals_json AS cluster_signature
                    FROM ecosystem_clusters
                    ORDER BY cluster_signature
                )
                """
            ) ?? "no-clusters"
            let recommendationSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(recommendation_signature, '|'), 'no-recommendations')
                FROM (
                    SELECT source_repository_id || ':' || target_node_id || ':' || recommendation_type || ':' ||
                           score || ':' || explanation || ':' || signals_json AS recommendation_signature
                    FROM repository_recommendations
                    ORDER BY recommendation_signature
                )
                """
            ) ?? "no-recommendations"
            let graphSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(edge_signature, '|'), 'no-graph')
                FROM (
                    SELECT source.key || '>' || target.key || ':' || e.relationship_type || ':' || e.confidence || ':' ||
                           COALESCE(e.evidence_path, '') || ':' || COALESCE(e.evidence_text, '') || ':' || e.created_by
                           AS edge_signature
                    FROM graph_edges e
                    JOIN graph_nodes source ON source.id = e.source_node_id
                    JOIN graph_nodes target ON target.id = e.target_node_id
                    ORDER BY edge_signature
                )
                """
            ) ?? "no-graph"
            let stackSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(stack_signature, '|'), 'no-stack')
                FROM (
                    SELECT repository_id || ':' || name || ':' || category || ':' || confidence || ':' ||
                           COALESCE(evidence_path, '') || ':' || COALESCE(evidence_text, '') AS stack_signature
                    FROM detected_stack_items
                    ORDER BY stack_signature
                )
                """
            ) ?? "no-stack"
            let scoreSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(score_signature, '|'), 'no-scores')
                FROM (
                    SELECT repository_id || ':' || setup_complexity || ':' || local_first_score || ':' ||
                           experimentation_priority || ':' || ecosystem_influence || ':' || personal_relevance || ':' ||
                           generated_at AS score_signature
                    FROM repository_scores
                    ORDER BY score_signature
                )
                """
            ) ?? "no-scores"
            let insightSignature = try String.fetchOne(
                db,
                sql: """
                SELECT COALESCE(GROUP_CONCAT(insight_signature, '|'), 'no-insights')
                FROM (
                    SELECT repository_id || ':' || summary || ':' || usefulness || ':' ||
                           classifications_json || ':' || relationship_hints_json AS insight_signature
                    FROM ai_insights
                    ORDER BY insight_signature
                )
                """
            ) ?? "no-insights"
            return [repositorySignature, ecosystemSignature, recommendationSignature, graphSignature, stackSignature, scoreSignature, insightSignature]
                .joined(separator: "|")
        }
    }

    func hasExplorationIndex(cacheKey: String) throws -> Bool {
        try read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM exploration_index_entries WHERE cache_key = ?",
                arguments: [cacheKey]
            ) ?? 0
            return count > 0
        }
    }

    func fetchExplorationIndexEntries(limit: Int = 300) throws -> [ExplorationIndexEntrySummary] {
        try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    id,
                    entry_type,
                    target_id,
                    repository_id,
                    title,
                    subtitle,
                    body,
                    ecosystem_name,
                    keywords_json,
                    signals_json,
                    score,
                    confidence
                FROM exploration_index_entries
                ORDER BY score DESC, confidence DESC, title
                LIMIT ?
                """,
                arguments: [limit]
            )
            return rows.map(ExplorationIndexEntrySummary.init(row:))
        }
    }

    func upsertExplorationQuery(_ query: ExplorationQueryRecord) throws {
        try write { db in
            try query.upsert(db)
        }
    }

    func fetchRecentExplorationQueries(limit: Int = 8) throws -> [ExplorationQueryRecord] {
        try read { db in
            try ExplorationQueryRecord
                .order(Column("last_used_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchFavoriteExplorationQueries(limit: Int = 8) throws -> [ExplorationQueryRecord] {
        try read { db in
            try ExplorationQueryRecord
                .filter(Column("is_favorite") == true)
                .order(Column("last_used_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchSemanticIndexCacheKey() throws -> String {
        let explorationKey = try fetchExplorationCacheKey()
        return "\(explorationKey)|\(Self.defaultEmbeddingModel)"
    }

    func hasSemanticIndex(cacheKey: String, model: String) throws -> Bool {
        try read { db in
            let state = try SemanticSearchCacheRecord.fetchOne(db, key: Self.semanticIndexStateQueryHash)
            guard state?.queryText == cacheKey else { return false }
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM embedding_chunks WHERE embedding_model = ?",
                arguments: [model]
            ) ?? 0
            return count > 0
        }
    }

    func fetchEmbeddingChunkCount(model: String) throws -> Int {
        try read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM embedding_chunks WHERE embedding_model = ?",
                arguments: [model]
            ) ?? 0
        }
    }

    func fetchEmbeddingChunks(model: String, repositoryID: String? = nil) throws -> [EmbeddingChunkSummary] {
        try read { db in
            let rows = try fetchEmbeddingChunkRows(db: db, model: model, repositoryID: repositoryID)
            return rows.map(EmbeddingChunkSummary.init(row:))
        }
    }

    func fetchEmbeddingChunkRecords(model: String, repositoryID: String? = nil) throws -> [EmbeddingChunkRecord] {
        try read { db in
            let rows = try fetchEmbeddingChunkRows(db: db, model: model, repositoryID: repositoryID, includeHash: true)
            return rows.map { row in
                EmbeddingChunkRecord(
                    id: row["id"],
                    repositoryID: row["repository_id"],
                    sourceType: row["source_type"],
                    sourcePath: row["source_path"],
                    chunkText: row["chunk_text"],
                    contentHash: row["content_hash"],
                    embeddingModel: row["embedding_model"],
                    embedding: row["embedding"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    private func fetchEmbeddingChunkRows(db: Database,
                                         model: String,
                                         repositoryID: String?,
                                         includeHash: Bool = false) throws -> [Row] {
        let columns = includeHash
            ? "id, repository_id, source_type, source_path, chunk_text, content_hash, embedding_model, embedding, created_at"
            : "id, repository_id, source_type, source_path, chunk_text, embedding_model, embedding"
        if let repositoryID {
            return try Row.fetchAll(
                db,
                sql: """
                SELECT \(columns)
                FROM embedding_chunks
                WHERE embedding_model = ? AND repository_id = ?
                """,
                arguments: [model, repositoryID]
            )
        }
        return try Row.fetchAll(
            db,
            sql: """
            SELECT \(columns)
            FROM embedding_chunks
            WHERE embedding_model = ?
            """,
            arguments: [model]
        )
    }

    func replaceEmbeddingChunks(model: String,
                                repositoryID: String?,
                                chunks: [EmbeddingChunkRecord],
                                cacheKey: String,
                                ingestionJob: IngestionJobRecord) throws {
        try write { db in
            if let repositoryID {
                try db.execute(
                    sql: "DELETE FROM embedding_chunks WHERE embedding_model = ? AND repository_id = ?",
                    arguments: [model, repositoryID]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM embedding_chunks WHERE embedding_model = ?",
                    arguments: [model]
                )
                try db.execute(sql: "DELETE FROM semantic_search_cache WHERE query_hash != ?",
                               arguments: [Self.semanticIndexStateQueryHash])
            }
            for chunk in chunks {
                try chunk.upsert(db)
            }
            try db.execute(
                sql: "DELETE FROM semantic_search_cache WHERE query_hash != ?",
                arguments: [Self.semanticIndexStateQueryHash]
            )
            if repositoryID == nil {
                let state = SemanticIndexState(cacheKey: cacheKey,
                                             chunkCount: chunks.count,
                                             embeddingModel: model)
                let stateJSON = String(data: try JSONEncoder().encode(state), encoding: .utf8) ?? "{}"
                let record = SemanticSearchCacheRecord(
                    queryHash: Self.semanticIndexStateQueryHash,
                    queryText: cacheKey,
                    resultsJSON: stateJSON,
                    createdAt: IntelligenceDatabase.iso8601String()
                )
                try record.upsert(db)
            }
            try ingestionJob.upsert(db)
        }
    }

    func upsertSemanticSearchCache(_ record: SemanticSearchCacheRecord) throws {
        try write { db in
            try record.upsert(db)
        }
    }

    func fetchSemanticSearchCache(queryHash: String) throws -> SemanticSearchCacheRecord? {
        try read { db in
            try SemanticSearchCacheRecord.fetchOne(db, key: queryHash)
        }
    }

    func clearSemanticSearchCache() throws {
        try write { db in
            try db.execute(
                sql: "DELETE FROM semantic_search_cache WHERE query_hash != ?",
                arguments: [Self.semanticIndexStateQueryHash]
            )
        }
    }

    func fetchIngestionJob(id: String) throws -> IngestionJobRecord? {
        try read { db in
            try IngestionJobRecord.fetchOne(db, key: id)
        }
    }

    func fetchIngestionJobs(repositoryID: String) throws -> [IngestionJobRecord] {
        try read { db in
            try IngestionJobRecord
                .filter(Column("repository_id") == repositoryID)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    func fetchActivePipelineJobs(repositoryID: String) throws -> [IngestionJobRecord] {
        try read { db in
            let pipelineTypes = Array(CatalogIntelligencePipelineJob.types)
            return try IngestionJobRecord
                .filter(Column("repository_id") == repositoryID)
                .filter(pipelineTypes.contains(Column("type")))
                .filter(["pending", "running"].contains(Column("status")))
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    func fetchLatestFailedPipelineJob(repositoryID: String) throws -> IngestionJobRecord? {
        try read { db in
            let pipelineTypes = Array(CatalogIntelligencePipelineJob.types)
            return try IngestionJobRecord
                .filter(Column("repository_id") == repositoryID)
                .filter(pipelineTypes.contains(Column("type")))
                .filter(Column("status") == "failed")
                .order(Column("completed_at").desc)
                .fetchOne(db)
        }
    }

    func fetchActiveIngestionJob(repositoryID: String, type: String) throws -> IngestionJobRecord? {
        try read { db in
            try IngestionJobRecord
                .filter(Column("repository_id") == repositoryID)
                .filter(Column("type") == type)
                .filter(["pending", "running"].contains(Column("status")))
                .order(Column("created_at").desc)
                .fetchOne(db)
        }
    }

    func fetchLatestRunbook(repositoryID: String) throws -> RepositoryRunbookRecord? {
        try read { db in
            try RepositoryRunbookRecord
                .filter(Column("repository_id") == repositoryID)
                .order(Column("updated_at").desc)
                .fetchOne(db)
        }
    }

    func fetchRunbook(evidenceSignature: String) throws -> RepositoryRunbookRecord? {
        try read { db in
            try RepositoryRunbookRecord
                .filter(Column("evidence_signature") == evidenceSignature)
                .order(Column("updated_at").desc)
                .fetchOne(db)
        }
    }

    func upsert(runbook: RepositoryRunbookRecord, ingestionJob: IngestionJobRecord) throws {
        try write { db in
            try runbook.upsert(db)
            try ingestionJob.upsert(db)
        }
    }

    func updateRunbookLastExportedAt(runbookID: String, exportedAt: String) throws {
        try write { db in
            try db.execute(sql: """
                UPDATE repository_runbooks
                SET last_exported_at = ?
                WHERE id = ?
                """,
                           arguments: [exportedAt, runbookID])
        }
    }

    func fetchIngestionJobSummaries() throws -> [QueueJobSummary] {
        try read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    j.id,
                    j.repository_id,
                    j.type,
                    j.status,
                    j.priority,
                    j.progress,
                    j.error,
                    j.created_at,
                    j.started_at,
                    j.completed_at,
                    r.full_name AS repository_full_name,
                    r.name AS repository_name,
                    c.status AS clone_status,
                    c.path AS clone_path,
                    c.last_error AS clone_last_error
                FROM ingestion_jobs j
                LEFT JOIN repositories r ON r.id = j.repository_id
                LEFT JOIN clone_states c ON c.repository_id = j.repository_id
                ORDER BY
                    CASE j.status
                        WHEN 'running' THEN 0
                        WHEN 'pending' THEN 1
                        WHEN 'failed' THEN 2
                        WHEN 'cancelled' THEN 3
                        WHEN 'completed' THEN 4
                        ELSE 5
                    END,
                    j.priority DESC,
                    j.created_at DESC
                """
            )
            return rows.map(QueueJobSummary.init(row:))
        }
    }

    func fetchRepository(forJobID jobID: String) throws -> RepositoryRecord? {
        try read { db in
            guard let job = try IngestionJobRecord.fetchOne(db, key: jobID),
                  let repositoryID = job.repositoryID else {
                return nil
            }
            return try RepositoryRecord.fetchOne(db, key: repositoryID)
        }
    }

    func cancelIngestionJob(id: String) throws {
        try write { db in
            guard var job = try IngestionJobRecord.fetchOne(db, key: id),
                  job.status == "pending" || job.status == "running" else {
                return
            }

            let cancelledAt = Self.iso8601String()
            job.status = "cancelled"
            job.progress = 1
            job.error = "Cancelled by user."
            job.completedAt = cancelledAt
            try job.upsert(db)

            if job.type == "clone_repo",
               let repositoryID = job.repositoryID,
               var cloneState = try CloneStateRecord.fetchOne(db, key: repositoryID) {
                cloneState.status = "cancelled"
                cloneState.lastError = "Cancelled by user."
                try cloneState.upsert(db)
            }
        }
    }

    func isIngestionJobCancelled(id: String) throws -> Bool {
        try read { db in
            let job = try IngestionJobRecord.fetchOne(db, key: id)
            return job?.status == "cancelled"
        }
    }

    func smokeTest() throws {
        try initialize()

        let now = Self.iso8601String()
        let repositoryID = "debug-smoke-repository"
        let jobID = "debug-smoke-ingestion-job"
        let staticJobID = "debug-smoke-static-analysis-job"
        let aiJobID = "debug-smoke-ai-analysis-job"
        let graphJobID = "debug-smoke-relationship-generation-job"
        let recommendationJobID = "debug-smoke-recommendation-generation-job"
        let ecosystemJobID = "debug-smoke-ecosystem-discovery-job"
        let explorationJobID = "debug-smoke-exploration-index-job"

        let repository = RepositoryRecord(
            id: repositoryID,
            host: "github.com",
            owner: "opensource-shelf",
            name: "smoke-test",
            fullName: "opensource-shelf/smoke-test",
            githubURL: "https://github.com/opensource-shelf/smoke-test",
            websiteURL: nil,
            defaultBranch: "main",
            localPath: nil,
            latestCommitSHA: nil,
            userStatus: "debug",
            addedAt: now,
            updatedAt: now,
            lastAnalyzedAt: nil
        )

        let metadata = RepositoryMetadataRecord(
            repositoryID: repositoryID,
            description: "Debug-only smoke test repository.",
            stars: 0,
            forks: 0,
            openIssues: 0,
            licenseSPDX: "MIT",
            topicsJSON: "[\"debug\",\"smoke-test\"]",
            primaryLanguage: "Swift",
            pushedAt: now,
            archived: false,
            fork: false
        )

        let cloneState = CloneStateRecord(
            repositoryID: repositoryID,
            status: "not_cloned",
            cloneMode: "metadata_only",
            path: nil,
            currentHead: nil,
            branchCount: 0,
            tagCount: 0,
            sizeBytes: 0,
            lastFetchAt: nil,
            lastError: nil
        )

        let job = IngestionJobRecord(
            id: jobID,
            repositoryID: repositoryID,
            type: "debug_smoke_test",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )

        try write { db in
            try repository.upsert(db)
            try metadata.upsert(db)
            try cloneState.upsert(db)
            try job.upsert(db)
        }

        let staticJob = IngestionJobRecord(
            id: staticJobID,
            repositoryID: repositoryID,
            type: "static_analysis",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )
        try replaceStaticAnalysis(
            repositoryID: repositoryID,
            files: [
                RepositoryFileRecord(
                    id: "debug-smoke-repository-file",
                    repositoryID: repositoryID,
                    path: "package.json",
                    fileType: "json",
                    category: "manifest",
                    sizeBytes: 42,
                    detectedAt: now
                )
            ],
            manifests: [
                RepositoryManifestRecord(
                    id: "debug-smoke-repository-manifest",
                    repositoryID: repositoryID,
                    path: "package.json",
                    type: "package_json",
                    ecosystem: "JavaScript",
                    evidenceText: "{\"dependencies\":{\"react\":\"latest\"}}",
                    detectedAt: now
                )
            ],
            stackItems: [
                DetectedStackItemRecord(
                    id: "debug-smoke-stack-item",
                    repositoryID: repositoryID,
                    name: "React",
                    category: "framework",
                    detectionSource: "dependency",
                    confidence: 0.95,
                    evidencePath: "package.json",
                    evidenceText: "react",
                    detectedAt: now
                )
            ],
            ingestionJob: staticJob
        )

        let fetchedRepository = try fetchRepository(id: repositoryID)
        let fetchedMetadata = try fetchMetadata(repositoryID: repositoryID)
        let fetchedCloneState = try fetchCloneState(repositoryID: repositoryID)
        let fetchedJob = try fetchIngestionJob(id: jobID)
        let fetchedStaticJob = try fetchIngestionJob(id: staticJobID)
        let fetchedManifests = try fetchRepositoryManifests(repositoryID: repositoryID)
        let fetchedStackItems = try fetchDetectedStackItems(repositoryID: repositoryID)
        let aiInsight = AIInsightRecord(
            id: "debug-smoke-ai-insight",
            repositoryID: repositoryID,
            cacheKey: "debug-smoke-ai-cache-key",
            modelName: "debug-model",
            promptVersion: "debug-prompt",
            commitSHA: nil,
            summary: "Debug AI summary.",
            usefulness: "Verifies AI insight persistence.",
            classificationsJSON: "[\"debug\"]",
            risksJSON: "[\"none\"]",
            relationshipHintsJSON: "[\"pairs with smoke tests\"]",
            rawJSON: "{\"summary\":\"Debug AI summary.\"}",
            generatedAt: now
        )
        let score = RepositoryScoreRecord(
            id: "debug-smoke-repository-score",
            repositoryID: repositoryID,
            cacheKey: "debug-smoke-ai-cache-key",
            setupComplexity: 1,
            localFirstScore: 8,
            experimentationPriority: 5,
            ecosystemInfluence: 1,
            personalRelevance: 6,
            generatedAt: now
        )
        let aiJob = IngestionJobRecord(
            id: aiJobID,
            repositoryID: repositoryID,
            type: "ai_analysis",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )
        try upsert(aiInsight: aiInsight, repositoryScore: score, ingestionJob: aiJob)
        let fetchedAIInsight = try fetchLatestAIInsight(repositoryID: repositoryID)
        let fetchedScore = try fetchRepositoryScore(cacheKey: "debug-smoke-ai-cache-key")
        let repositoryNode = GraphNode(
            id: "debug-smoke-repository-node",
            type: "repository",
            key: "repository:\(repositoryID)",
            label: "opensource-shelf/smoke-test",
            metadataJSON: "{}"
        )
        let ollamaNode = GraphNode(
            id: "debug-smoke-ollama-node",
            type: "ai_tool",
            key: "ai_tool:ollama",
            label: "Ollama",
            metadataJSON: "{}"
        )
        let graphEdge = GraphEdge(
            id: "debug-smoke-graph-edge",
            sourceNodeID: repositoryNode.id,
            targetNodeID: ollamaNode.id,
            relationshipType: "integrates_with",
            confidence: 0.95,
            evidenceText: "Debug graph persistence evidence.",
            evidencePath: "package.json",
            createdBy: "debug_smoke",
            createdAt: now
        )
        let graphJob = IngestionJobRecord(
            id: graphJobID,
            repositoryID: repositoryID,
            type: "relationship_generation",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )
        try upsertGraph(repositoryID: repositoryID,
                        nodes: [repositoryNode, ollamaNode],
                        edges: [graphEdge],
                        ingestionJob: graphJob)
        let fetchedRelationships = try fetchGraphRelationships(repositoryID: repositoryID)
        let recommendationCacheKey = try fetchRecommendationCacheKey(repositoryID: repositoryID)
        let recommendationJob = IngestionJobRecord(
            id: recommendationJobID,
            repositoryID: repositoryID,
            type: "recommendation_generation",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )
        let recommendation = RepositoryRecommendationRecord(
            id: "debug-smoke-recommendation",
            sourceRepositoryID: repositoryID,
            targetNodeID: ollamaNode.id,
            targetRepositoryID: nil,
            recommendationType: "ai_tooling_stack",
            score: 88,
            explanation: "Ollama fits the local AI stack.",
            signalsJSON: "[\"relationship confidence 95%\",\"deterministic evidence\"]",
            cacheKey: recommendationCacheKey,
            generatedAt: now
        )
        try replaceRecommendations(repositoryID: repositoryID,
                                   cacheKey: recommendationCacheKey,
                                   recommendations: [recommendation],
                                   ingestionJob: recommendationJob)
        let fetchedRecommendations = try fetchRecommendations(repositoryID: repositoryID)
        let ecosystemCacheKey = try fetchEcosystemCacheKey()
        let ecosystemJob = IngestionJobRecord(
            id: ecosystemJobID,
            repositoryID: nil,
            type: "ecosystem_discovery",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )
        let ecosystemCluster = EcosystemClusterRecord(
            id: "debug-smoke-ecosystem-cluster",
            clusterType: "ecosystem",
            name: "Local AI",
            score: 82,
            confidence: 0.9,
            repositoryIDsJSON: "[\"\(repositoryID)\"]",
            repositoryNamesJSON: "[\"opensource-shelf/smoke-test\"]",
            commonStackJSON: "[\"React\",\"Ollama\"]",
            strongestToolsJSON: "[\"Ollama\"]",
            integrationsJSON: "[\"Ollama\"]",
            recommendationHighlightsJSON: "[\"Ollama fits the local AI stack.\"]",
            missingPiecesJSON: "[\"Debug missing piece suggestion.\"]",
            signalsJSON: "[\"1 repositories\",\"1 relationships\"]",
            explanation: "Debug ecosystem cluster.",
            cacheKey: ecosystemCacheKey,
            generatedAt: now
        )
        try replaceEcosystemClusters(cacheKey: ecosystemCacheKey,
                                     clusters: [ecosystemCluster],
                                     ingestionJob: ecosystemJob)
        let fetchedEcosystems = try fetchEcosystemClusters(types: ["ecosystem"])
        let explorationCacheKey = try fetchExplorationCacheKey()
        let explorationJob = IngestionJobRecord(
            id: explorationJobID,
            repositoryID: nil,
            type: "exploration_index_refresh",
            status: "completed",
            priority: 0,
            progress: 1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: now
        )
        let explorationEntry = ExplorationIndexEntryRecord(
            id: "debug-smoke-exploration-entry",
            entryType: "repository",
            targetID: repositoryID,
            repositoryID: repositoryID,
            title: "opensource-shelf/smoke-test",
            subtitle: "Debug AI summary.",
            body: "Ollama fits the local AI stack.",
            ecosystemName: "Local AI",
            keywordsJSON: "[\"local ai\",\"ollama\",\"react\",\"mcp\"]",
            signalsJSON: "[\"relationship confidence 95%\",\"deterministic evidence\"]",
            score: 88,
            confidence: 0.9,
            cacheKey: explorationCacheKey,
            generatedAt: now
        )
        try replaceExplorationIndex(cacheKey: explorationCacheKey,
                                    entries: [explorationEntry],
                                    ingestionJob: explorationJob)
        let explorationQuery = ExplorationQueryRecord(
            id: "debug-smoke-exploration-query",
            queryText: "show local ai tools",
            normalizedIntent: "ai_tooling",
            filtersJSON: "[\"local_ai\"]",
            resultIDsJSON: "[\"debug-smoke-exploration-entry\"]",
            isFavorite: false,
            createdAt: now,
            lastUsedAt: now
        )
        try upsertExplorationQuery(explorationQuery)
        let fetchedExplorationEntries = try fetchExplorationIndexEntries()
        let fetchedExplorationQueries = try fetchRecentExplorationQueries()

        let dummyVector = VectorMath.encode([0.1, 0.2, 0.3, 0.4])
        let embeddingChunk = EmbeddingChunkRecord(
            id: "debug-smoke-embedding-chunk",
            repositoryID: repositoryID,
            sourceType: "ai_summary",
            sourcePath: "ai_insight",
            chunkText: "Debug AI summary for local-first tooling.",
            contentHash: "debug-smoke-hash",
            embeddingModel: Self.defaultEmbeddingModel,
            embedding: dummyVector,
            createdAt: now
        )
        let semanticCache = SemanticSearchCacheRecord(
            queryHash: "debug-smoke-semantic-query-hash",
            queryText: "privacy-focused local ai",
            resultsJSON: "[{\"id\":\"debug-smoke-embedding-chunk\",\"repositoryID\":\"\(repositoryID)\",\"sourceType\":\"ai_summary\",\"chunkText\":\"Debug AI summary for local-first tooling.\",\"similarity\":0.82}]",
            createdAt: now
        )
        try write { db in
            try embeddingChunk.upsert(db)
            try semanticCache.upsert(db)
        }
        let fetchedChunks = try fetchEmbeddingChunks(model: Self.defaultEmbeddingModel, repositoryID: repositoryID)
        let fetchedSemanticCache = try fetchSemanticSearchCache(queryHash: semanticCache.queryHash)

        let graphLayoutCache = GraphLayoutCacheRecord(
            focusRepositoryID: repositoryID,
            cacheKey: "debug-smoke-graph-layout",
            layoutJSON: "{\"cacheKey\":\"debug-smoke-graph-layout\",\"positions\":{}}",
            createdAt: now
        )
        try upsertGraphLayoutCache(graphLayoutCache)
        let fetchedGraphLayoutCache = try fetchGraphLayoutCache(focusRepositoryID: repositoryID)
        let graphNeighborhood = try fetchGraphNeighborhood(repositoryID: repositoryID,
                                                           filters: GraphFilterState(),
                                                           maxNodes: 12,
                                                           maxEdges: 16)

        let graphPath = GraphPathResult(fromNodeID: repositoryNode.id,
                                        toNodeID: ollamaNode.id,
                                        fromLabel: repositoryNode.label,
                                        toLabel: ollamaNode.label,
                                        steps: [],
                                        hopCount: 0,
                                        explanation: "Debug path cache entry.")
        let graphPathCache = GraphPathCacheRecord(cacheKey: "\(repositoryNode.id)|\(ollamaNode.id)|0.35",
                                                  pathJSON: "{\"fromNodeID\":\"\(repositoryNode.id)\",\"toNodeID\":\"\(ollamaNode.id)\",\"fromLabel\":\"\(repositoryNode.label)\",\"toLabel\":\"\(ollamaNode.label)\",\"steps\":[],\"hopCount\":0,\"explanation\":\"Debug path cache entry.\"}",
                                                  createdAt: now)
        try upsertGraphPathCache(graphPathCache)
        let fetchedGraphPathCache = try fetchGraphPathCache(cacheKey: graphPathCache.cacheKey)

        let navigationSnapshot = GraphNavigationSnapshot(recentSearches: ["Ollama"],
                                                         recentFocusRepositoryIDs: [repositoryID],
                                                         trail: [])
        let navigationCache = GraphNavigationCacheRecord(cacheID: "default",
                                                         payloadJSON: "{\"recentSearches\":[\"Ollama\"],\"recentFocusRepositoryIDs\":[\"\(repositoryID)\"],\"trail\":[]}",
                                                         updatedAt: now)
        try upsertGraphNavigationCache(navigationCache)
        let fetchedNavigationCache = try fetchGraphNavigationCache()
        _ = graphPath
        _ = navigationSnapshot

        let comparisonSignature = try comparisonEvidenceSignature(repositoryIDs: [repositoryID])
        let comparisonSession = ComparisonSessionRecord(
            id: repositoryID,
            repositoryIDsJSON: "[\"\(repositoryID)\"]",
            title: "opensource-shelf/smoke-test",
            isFavorite: false,
            createdAt: now,
            updatedAt: now
        )
        try upsertComparisonSession(comparisonSession)
        let comparisonCache = ComparisonResultsCacheRecord(
            cacheSignature: "debug-smoke-compare-cache",
            repositoryIDsJSON: "[\"\(repositoryID)\"]",
            resultJSON: "{\"profiles\":[],\"rankings\":[],\"sharedStack\":[],\"uniqueStack\":{},\"sharedEcosystems\":[],\"uniqueRisks\":{},\"uniqueStrengths\":{},\"graphOverlap\":{\"sharedNeighbors\":[],\"pairPaths\":[],\"sharedIntegrations\":[],\"alternativeLinks\":[]},\"decisionSummary\":[],\"matrixRows\":[],\"cacheSignature\":\"\(comparisonSignature)\",\"generatedAt\":\"\(now)\"}",
            createdAt: now
        )
        try upsertComparisonResultsCache(comparisonCache)
        try setComparisonSessionFavorite(id: comparisonSession.id, isFavorite: true)
        let fetchedComparisonSession = try fetchRecentComparisonSessions(limit: 1).first
        let fetchedFavoriteSession = try fetchFavoriteComparisonSessions(limit: 1).first
        let fetchedComparisonCache = try fetchComparisonResultsCache(cacheSignature: comparisonCache.cacheSignature)
        _ = comparisonSignature

        guard fetchedRepository != nil,
              fetchedMetadata != nil,
              fetchedCloneState != nil,
              fetchedJob != nil,
              fetchedStaticJob != nil,
              !fetchedManifests.isEmpty,
              !fetchedStackItems.isEmpty,
              fetchedAIInsight != nil,
              fetchedScore != nil,
              !fetchedRelationships.isEmpty,
              !fetchedRecommendations.isEmpty,
              !fetchedEcosystems.isEmpty,
              !fetchedExplorationEntries.isEmpty,
              !fetchedExplorationQueries.isEmpty,
              !fetchedChunks.isEmpty,
              fetchedSemanticCache != nil,
              fetchedGraphLayoutCache != nil,
              fetchedGraphPathCache != nil,
              fetchedNavigationCache != nil,
              fetchedComparisonSession != nil,
              fetchedFavoriteSession != nil,
              fetchedComparisonCache != nil else {
            throw IntelligenceDatabaseError.notInitialized
        }
        _ = graphNeighborhood

        #if DEBUG
        print("[reshelf] Intelligence database smoke test passed at \(databaseURL.path)")
        #endif
    }

    #if DEBUG
    func debugSchemaSummary() throws -> String {
        try read { db in
            let migrations = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"
            )
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )

            return """
            database=\(databaseURL.path)
            migrations=\(migrations.joined(separator: ","))
            tables=\(tables.joined(separator: ","))
            """
        }
    }
    #endif

    static func iso8601String(from date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func requireDatabaseQueue() throws -> DatabaseQueue {
        guard let databaseQueue else {
            throw IntelligenceDatabaseError.notInitialized
        }
        return databaseQueue
    }

    private func upsertGraphEdge(_ edge: GraphEdge, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO graph_edges (
                id,
                source_node_id,
                target_node_id,
                relationship_type,
                confidence,
                evidence_text,
                evidence_path,
                created_by,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_node_id, target_node_id, relationship_type) DO UPDATE SET
                confidence = CASE
                    WHEN excluded.confidence > graph_edges.confidence THEN excluded.confidence
                    ELSE graph_edges.confidence
                END,
                evidence_text = CASE
                    WHEN excluded.confidence >= graph_edges.confidence THEN excluded.evidence_text
                    ELSE graph_edges.evidence_text
                END,
                evidence_path = CASE
                    WHEN excluded.confidence >= graph_edges.confidence THEN excluded.evidence_path
                    ELSE graph_edges.evidence_path
                END,
                created_by = CASE
                    WHEN excluded.confidence >= graph_edges.confidence THEN excluded.created_by
                    ELSE graph_edges.created_by
                END,
                created_at = excluded.created_at
            """,
            arguments: [
                edge.id,
                edge.sourceNodeID,
                edge.targetNodeID,
                edge.relationshipType,
                edge.confidence,
                edge.evidenceText,
                edge.evidencePath,
                edge.createdBy,
                edge.createdAt
            ]
        )
    }

    private func deleteOutgoingGraphEdges(repositoryID: String, db: Database) throws {
        try db.execute(
            sql: """
            DELETE FROM graph_edges
            WHERE source_node_id IN (
                SELECT id FROM graph_nodes
                WHERE key = ?
            )
            """,
            arguments: ["repository:\(repositoryID)"]
        )
    }

    private func repairLegacyOrphanRows(in queue: DatabaseQueue) throws {
        try queue.write { db in
            let tables = Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))
            guard tables.contains("repositories") else {
                return
            }

            if tables.contains("repository_metadata") {
                try db.execute(sql: """
                    DELETE FROM repository_metadata
                    WHERE NOT EXISTS (
                        SELECT 1 FROM repositories
                        WHERE repositories.id = repository_metadata.repository_id
                    )
                    """)
            }

            if tables.contains("clone_states") {
                try db.execute(sql: """
                    DELETE FROM clone_states
                    WHERE NOT EXISTS (
                        SELECT 1 FROM repositories
                        WHERE repositories.id = clone_states.repository_id
                    )
                    """)
            }

            if tables.contains("ingestion_jobs") {
                try db.execute(sql: """
                    UPDATE ingestion_jobs
                    SET repository_id = NULL
                    WHERE repository_id IS NOT NULL
                    AND NOT EXISTS (
                        SELECT 1 FROM repositories
                        WHERE repositories.id = ingestion_jobs.repository_id
                    )
                    """)
            }
        }
    }
}
