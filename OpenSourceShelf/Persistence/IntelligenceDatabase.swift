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

    private let initializeLock = NSLock()

    func initialize() throws {
        // Serialized: initialize() is called from several services, and an
        // unsynchronized check-then-assign let two threads race to create two
        // DatabaseQueues over the same file.
        initializeLock.lock()
        defer { initializeLock.unlock() }
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

    func fetchRepository(forJobID jobID: String) throws -> RepositoryRecord? {
        try read { db in
            guard let job = try IngestionJobRecord.fetchOne(db, key: jobID),
                  let repositoryID = job.repositoryID else {
                return nil
            }
            return try RepositoryRecord.fetchOne(db, key: repositoryID)
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
