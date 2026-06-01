import Foundation

struct RepositoryStaticAnalysisResult: Equatable {
    let repositoryID: String
    let files: [RepositoryFileRecord]
    let manifests: [RepositoryManifestRecord]
    let stackItems: [DetectedStackItemRecord]
    let ingestionJob: IngestionJobRecord
}

enum RepositoryStaticAnalysisError: LocalizedError {
    case missingLocalPath
    case repositoryPathMissing(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingLocalPath:
            return "Repository does not have a local clone path."
        case let .repositoryPathMissing(path):
            return "Repository path does not exist: \(path)"
        case .cancelled:
            return "Static analysis was cancelled."
        }
    }
}

enum RepositoryStaticAnalyzer {
    static let excludedDirectoryNames: Set<String> = [
        ".git",
        "node_modules",
        "dist",
        "build",
        "target",
        "DerivedData",
        "vendor",
        "coverage"
    ]

    static func analyze(repository: RepositoryRecord,
                        database: IntelligenceDatabase = .shared,
                        fileManager: FileManager = .default,
                        jobID: String? = nil) async throws -> RepositoryStaticAnalysisResult {
        try database.initialize()

        guard let localPath = repository.localPath, !localPath.isEmpty else {
            throw RepositoryStaticAnalysisError.missingLocalPath
        }

        let rootURL = URL(fileURLWithPath: localPath, isDirectory: true)
        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw RepositoryStaticAnalysisError.repositoryPathMissing(rootURL.path)
        }

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(
            id: jobID ?? UUID().uuidString,
            repositoryID: repository.id,
            type: "static_analysis",
            status: "running",
            priority: 0,
            progress: 0.1,
            error: nil,
            createdAt: now,
            startedAt: now,
            completedAt: nil
        )

        try database.upsert(ingestionJob: job)
        try throwIfCancelled(jobID: job.id, database: database)

        do {
            let entries = try await inventoryEntries(rootURL: rootURL, fileManager: fileManager)
            let manifestDetections = ManifestDetector.detect(in: entries, rootURL: rootURL, fileManager: fileManager)

            job.progress = 0.35
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)

            let stackDetections = StackDetectionService.detect(entries: entries,
                                                               manifests: manifestDetections,
                                                               fileManager: fileManager)

            job.progress = 0.7
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)

            let completedAt = IntelligenceDatabase.iso8601String()
            let manifestPaths = Set(manifestDetections.map(\.path))
            let files = importantFileRecords(from: entries,
                                             manifestPaths: manifestPaths,
                                             repositoryID: repository.id,
                                             detectedAt: completedAt)
            let manifests = manifestDetections.map { detection in
                RepositoryManifestRecord(id: UUID().uuidString,
                                         repositoryID: repository.id,
                                         path: detection.path,
                                         type: detection.type,
                                         ecosystem: detection.ecosystem,
                                         evidenceText: detection.evidenceText,
                                         detectedAt: completedAt)
            }
            let stackItems = stackDetections.map { detection in
                DetectedStackItemRecord(id: UUID().uuidString,
                                        repositoryID: repository.id,
                                        name: detection.name,
                                        category: detection.category,
                                        detectionSource: detection.detectionSource,
                                        confidence: detection.confidence,
                                        evidencePath: detection.evidencePath,
                                        evidenceText: detection.evidenceText,
                                        detectedAt: completedAt)
            }

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt

            try database.replaceStaticAnalysis(repositoryID: repository.id,
                                               files: files,
                                               manifests: manifests,
                                               stackItems: stackItems,
                                               ingestionJob: job)

            do {
                _ = try await RepositoryAIAnalyzer.analyze(repository: repository, database: database)
            } catch {
                #if DEBUG
                print("[reshelf] AI analysis failed for \(repository.fullName): \(error)")
                #endif
            }

            return RepositoryStaticAnalysisResult(repositoryID: repository.id,
                                                  files: files,
                                                  manifests: manifests,
                                                  stackItems: stackItems,
                                                  ingestionJob: job)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true || error is CancellationError {
                job.status = "cancelled"
                job.progress = 1
                job.error = "Cancelled by user."
                job.completedAt = IntelligenceDatabase.iso8601String()
                try? database.upsert(ingestionJob: job)
                throw RepositoryStaticAnalysisError.cancelled
            }

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = IntelligenceDatabase.iso8601String()
            try? database.upsert(ingestionJob: job)
            throw error
        }
    }

    private static func inventoryEntries(rootURL: URL,
                                         fileManager: FileManager) async throws -> [RepositoryInventoryEntry] {
        try await Task.detached(priority: .utility) {
            try scanInventoryEntries(rootURL: rootURL, fileManager: fileManager)
        }.value
    }

    private static func scanInventoryEntries(rootURL: URL,
                                             fileManager: FileManager) throws -> [RepositoryInventoryEntry] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else {
            return []
        }

        var entries: [RepositoryInventoryEntry] = []
        for case let url as URL in enumerator {
            if Task.isCancelled {
                throw CancellationError()
            }

            let relativePath = relativePath(for: url, rootURL: rootURL)
            let pathComponents = relativePath.split(separator: "/").map(String.init)
            guard let lastComponent = pathComponents.last else { continue }

            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = resourceValues?.isDirectory == true

            if isDirectory, excludedDirectoryNames.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }
            if pathComponents.contains(where: excludedDirectoryNames.contains) {
                continue
            }
            if isDirectory, pathComponents.count > 6 {
                enumerator.skipDescendants()
                continue
            }

            entries.append(RepositoryInventoryEntry(relativePath: relativePath,
                                                    url: url,
                                                    isDirectory: isDirectory,
                                                    sizeBytes: resourceValues?.fileSize.map(Int64.init),
                                                    depth: pathComponents.count))

            if entries.count >= 8_000 {
                break
            }
        }

        return entries
    }

    private static func importantFileRecords(from entries: [RepositoryInventoryEntry],
                                             manifestPaths: Set<String>,
                                             repositoryID: String,
                                             detectedAt: String) -> [RepositoryFileRecord] {
        entries.compactMap { entry in
            guard let category = category(for: entry, manifestPaths: manifestPaths) else {
                return nil
            }

            let fileType = entry.isDirectory
                ? "directory"
                : URL(fileURLWithPath: entry.relativePath).pathExtension.lowercased()

            return RepositoryFileRecord(id: UUID().uuidString,
                                        repositoryID: repositoryID,
                                        path: entry.relativePath,
                                        fileType: fileType.isEmpty ? "file" : fileType,
                                        category: category,
                                        sizeBytes: entry.sizeBytes,
                                        detectedAt: detectedAt)
        }
        .sorted { $0.path < $1.path }
    }

    private static func category(for entry: RepositoryInventoryEntry,
                                 manifestPaths: Set<String>) -> String? {
        if manifestPaths.contains(entry.relativePath) {
            return "manifest"
        }
        if entry.relativePath == ".cursor" {
            return "config"
        }
        if entry.relativePath.hasPrefix(".github/workflows/")
            || entry.relativePath == ".gitlab-ci.yml"
            || entry.relativePath == "Jenkinsfile" {
            return "ci"
        }
        if entry.relativePath.hasPrefix("docs/")
            || ["md", "markdown", "rst", "adoc"].contains(URL(fileURLWithPath: entry.relativePath).pathExtension.lowercased()) {
            return "docs"
        }
        if entry.depth == 1 {
            return "root"
        }
        if isConfigPath(entry.relativePath) {
            return "config"
        }
        return nil
    }

    private static func isConfigPath(_ path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        return fileName.hasSuffix(".config.js")
            || fileName.hasSuffix(".config.ts")
            || fileName.hasSuffix(".toml")
            || fileName.hasSuffix(".yaml")
            || fileName.hasSuffix(".yml")
            || fileName.hasSuffix(".json")
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }

        let offset = path.index(path.startIndex, offsetBy: rootPath.count)
        return path[offset...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func throwIfCancelled(jobID: String, database: IntelligenceDatabase) throws {
        if try database.isIngestionJobCancelled(id: jobID) {
            throw RepositoryStaticAnalysisError.cancelled
        }
    }
}
