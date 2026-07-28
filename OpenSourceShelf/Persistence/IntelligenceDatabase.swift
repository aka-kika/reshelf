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






    func clearGraphPathCache() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM graph_path_cache")
        }
    }



    func clearGraphNavigationCache() throws {
        try write { db in
            try db.execute(sql: "DELETE FROM graph_navigation_cache")
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


    func deleteComparisonSession(id: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM comparison_sessions WHERE id = ?", arguments: [id])
        }
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
        }
        return parts.joined(separator: "|")
    }





    private func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
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
