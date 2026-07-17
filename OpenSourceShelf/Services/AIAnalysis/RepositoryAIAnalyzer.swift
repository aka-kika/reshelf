import Foundation

struct RepositoryAIAnalysisResult: Equatable {
    let insight: AIInsightRecord
    let score: RepositoryScoreRecord
    let ingestionJob: IngestionJobRecord
    let usedCache: Bool
}

struct RepositoryAIAnalysisPayload: Codable, Equatable {
    var summary: String
    var usefulness: String
    var classifications: [String]
    var risks: [String]
    var setupComplexity: Int
    var localFirstScore: Int
    var experimentationPriority: Int
    var personalRelevance: Int
    var relationshipHints: [String]
}

enum RepositoryAIAnalysisError: LocalizedError {
    case missingRepositoryPath
    case malformedJSON
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingRepositoryPath:
            return "Repository does not have a local path for README evidence."
        case .malformedJSON:
            return "Ollama returned malformed JSON."
        case .cancelled:
            return "AI analysis was cancelled."
        }
    }
}

enum RepositoryAIAnalyzer {
    static func analyze(repository: RepositoryRecord,
                        database: IntelligenceDatabase = .shared,
                        baseURL: String = AIAnalysisCache.baseURL,
                        modelName: String = AIAnalysisCache.modelName,
                        promptVersion: String = AIAnalysisCache.promptVersion,
                        fileManager: FileManager = .default,
                        jobID: String? = nil) async throws -> RepositoryAIAnalysisResult {
        try database.initialize()

        let usesAppleIntelligence = AISettingsSnapshot.resolvedProvider() == .appleIntelligence
            && AppleIntelligenceService.availability.isAvailable
        let effectiveModelName = usesAppleIntelligence ? AppleIntelligenceService.modelIdentifier : modelName

        let cacheKey = AIAnalysisCache.cacheKey(repositoryID: repository.id,
                                                commitSHA: repository.latestCommitSHA,
                                                modelName: effectiveModelName,
                                                promptVersion: promptVersion)
        if let cachedInsight = try database.fetchAIInsight(cacheKey: cacheKey),
           let cachedScore = try database.fetchRepositoryScore(cacheKey: cacheKey) {
            let cachedJob = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                               repositoryID: repository.id,
                                               type: "ai_analysis",
                                               status: "completed",
                                               priority: 0,
                                               progress: 1,
                                               error: "Used cached AI analysis.",
                                               createdAt: IntelligenceDatabase.iso8601String(),
                                               startedAt: IntelligenceDatabase.iso8601String(),
                                               completedAt: IntelligenceDatabase.iso8601String())
            try database.upsert(ingestionJob: cachedJob)
            await generateRelationshipsIfPossible(repository: repository, database: database)
            return RepositoryAIAnalysisResult(insight: cachedInsight,
                                              score: cachedScore,
                                              ingestionJob: cachedJob,
                                              usedCache: true)
        }

        let now = IntelligenceDatabase.iso8601String()
        var job = IngestionJobRecord(id: jobID ?? UUID().uuidString,
                                     repositoryID: repository.id,
                                     type: "ai_analysis",
                                     status: "running",
                                     priority: 0,
                                     progress: 0.15,
                                     error: nil,
                                     createdAt: now,
                                     startedAt: now,
                                     completedAt: nil)
        try database.upsert(ingestionJob: job)

        do {
            try throwIfCancelled(jobID: job.id, database: database)
            let evidence = try collectEvidence(repository: repository,
                                               database: database,
                                               fileManager: fileManager)

            job.progress = 0.35
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)

            let payload: RepositoryAIAnalysisPayload
            let rawJSON: String
            if usesAppleIntelligence {
                payload = try await analyzeWithAppleIntelligence(evidence: evidence)
                rawJSON = encodePayloadJSON(payload)
            } else {
                let prompt = AIAnalysisPromptBuilder.buildPrompt(evidence: evidence)
                rawJSON = try await OllamaService.generateJSONCompletion(baseURL: baseURL,
                                                                         model: modelName,
                                                                         prompt: prompt,
                                                                         timeout: 45,
                                                                         retries: 1)
                payload = try parsePayload(from: rawJSON)
            }

            job.progress = 0.75
            try database.upsert(ingestionJob: job)
            try throwIfCancelled(jobID: job.id, database: database)
            let completedAt = IntelligenceDatabase.iso8601String()
            let normalized = normalize(payload)
            let classificationsJSON = try encodeStringArray(normalized.classifications)
            let risksJSON = try encodeStringArray(normalized.risks)
            let relationshipHintsJSON = try encodeStringArray(normalized.relationshipHints)
            let ecosystemInfluence = ecosystemInfluenceScore(metadata: evidence.metadata,
                                                             stackItems: evidence.stackItems)

            let insight = AIInsightRecord(id: UUID().uuidString,
                                          repositoryID: repository.id,
                                          cacheKey: cacheKey,
                                          modelName: effectiveModelName,
                                          promptVersion: promptVersion,
                                          commitSHA: repository.latestCommitSHA,
                                          summary: normalized.summary,
                                          usefulness: normalized.usefulness,
                                          classificationsJSON: classificationsJSON,
                                          risksJSON: risksJSON,
                                          relationshipHintsJSON: relationshipHintsJSON,
                                          rawJSON: rawJSON,
                                          generatedAt: completedAt)
            let score = RepositoryScoreRecord(id: UUID().uuidString,
                                              repositoryID: repository.id,
                                              cacheKey: cacheKey,
                                              setupComplexity: normalized.setupComplexity,
                                              localFirstScore: normalized.localFirstScore,
                                              experimentationPriority: normalized.experimentationPriority,
                                              ecosystemInfluence: ecosystemInfluence,
                                              personalRelevance: normalized.personalRelevance,
                                              generatedAt: completedAt)

            job.status = "completed"
            job.progress = 1
            job.completedAt = completedAt
            try database.upsert(aiInsight: insight, repositoryScore: score, ingestionJob: job)
            await generateRelationshipsIfPossible(repository: repository, database: database)

            return RepositoryAIAnalysisResult(insight: insight,
                                              score: score,
                                              ingestionJob: job,
                                              usedCache: false)
        } catch {
            if (try? database.isIngestionJobCancelled(id: job.id)) == true || error is CancellationError {
                job.status = "cancelled"
                job.progress = 1
                job.error = "Cancelled by user."
                job.completedAt = IntelligenceDatabase.iso8601String()
                try? database.upsert(ingestionJob: job)
                throw RepositoryAIAnalysisError.cancelled
            }

            job.status = "failed"
            job.progress = 1
            job.error = error.localizedDescription
            job.completedAt = IntelligenceDatabase.iso8601String()
            try? database.upsert(ingestionJob: job)
            throw error
        }
    }

    private static func collectEvidence(repository: RepositoryRecord,
                                        database: IntelligenceDatabase,
                                        fileManager: FileManager) throws -> AIAnalysisEvidence {
        let metadata = try database.fetchMetadata(repositoryID: repository.id)
        let manifests = try database.fetchRepositoryManifests(repositoryID: repository.id)
        let stackItems = try database.fetchDetectedStackItems(repositoryID: repository.id)
        let readmeExcerpt = readmeExcerpt(repository: repository, fileManager: fileManager)

        return AIAnalysisEvidence(repository: repository,
                                  metadata: metadata,
                                  readmeExcerpt: readmeExcerpt,
                                  stackItems: stackItems,
                                  manifests: manifests)
    }

    private static func readmeExcerpt(repository: RepositoryRecord,
                                      fileManager: FileManager) -> String? {
        guard let localPath = repository.localPath else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: localPath, isDirectory: true)
        let candidates = ["README.md", "Readme.md", "readme.md", "README", "README.markdown", "README.rst"]
        for candidate in candidates {
            let url = rootURL.appendingPathComponent(candidate)
            guard fileManager.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            return String(text.prefix(5_000))
        }
        return nil
    }

    /// Guided generation via the on-device model; retries once with trimmed evidence
    /// if the prompt exceeds the model's context window.
    private static func analyzeWithAppleIntelligence(evidence: AIAnalysisEvidence) async throws -> RepositoryAIAnalysisPayload {
        do {
            let prompt = AIAnalysisPromptBuilder.buildGuidedPrompt(evidence: evidence)
            return try await AppleIntelligenceService.analyzeRepository(prompt: prompt)
        } catch AppleIntelligenceService.GenerationFailure.contextWindowExceeded {
            var compact = evidence
            compact.readmeExcerpt = evidence.readmeExcerpt.map { String($0.prefix(1_500)) }
            compact.stackItems = Array(evidence.stackItems.prefix(12))
            compact.manifests = Array(evidence.manifests.prefix(8))
            let prompt = AIAnalysisPromptBuilder.buildGuidedPrompt(evidence: compact)
            return try await AppleIntelligenceService.analyzeRepository(prompt: prompt)
        }
    }

    private static func encodePayloadJSON(_ payload: RepositoryAIAnalysisPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func parsePayload(from rawOutput: String) throws -> RepositoryAIAnalysisPayload {
        let jsonText = extractJSONObject(from: rawOutput)
        guard let data = jsonText.data(using: .utf8) else {
            throw RepositoryAIAnalysisError.malformedJSON
        }

        do {
            return try JSONDecoder().decode(RepositoryAIAnalysisPayload.self, from: data)
        } catch {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RepositoryAIAnalysisError.malformedJSON
            }
            return RepositoryAIAnalysisPayload(
                summary: object["summary"] as? String ?? "",
                usefulness: object["usefulness"] as? String ?? "",
                classifications: stringArray(from: object["classifications"]),
                risks: stringArray(from: object["risks"]),
                setupComplexity: intScore(from: object["setupComplexity"]),
                localFirstScore: intScore(from: object["localFirstScore"]),
                experimentationPriority: intScore(from: object["experimentationPriority"]),
                personalRelevance: intScore(from: object["personalRelevance"]),
                relationshipHints: stringArray(from: object["relationshipHints"])
            )
        }
    }

    private static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }

    private static func normalize(_ payload: RepositoryAIAnalysisPayload) -> RepositoryAIAnalysisPayload {
        RepositoryAIAnalysisPayload(summary: payload.summary.trimmedLimited(to: 700),
                                    usefulness: payload.usefulness.trimmedLimited(to: 900),
                                    classifications: payload.classifications.normalizedStrings(limit: 8),
                                    risks: payload.risks.normalizedStrings(limit: 8),
                                    setupComplexity: clampScore(payload.setupComplexity),
                                    localFirstScore: clampScore(payload.localFirstScore),
                                    experimentationPriority: clampScore(payload.experimentationPriority),
                                    personalRelevance: clampScore(payload.personalRelevance),
                                    relationshipHints: payload.relationshipHints.normalizedStrings(limit: 8))
    }

    private static func encodeStringArray(_ values: [String]) throws -> String {
        let data = try JSONEncoder().encode(values)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func stringArray(from value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }
        }
        if let value = value as? String, !value.isEmpty {
            return [value]
        }
        return []
    }

    private static func intScore(from value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Double {
            return Int(value.rounded())
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String, let parsed = Int(value) {
            return parsed
        }
        return 0
    }

    private static func ecosystemInfluenceScore(metadata: RepositoryMetadataRecord?,
                                                stackItems: [DetectedStackItemRecord]) -> Int {
        let stars = metadata?.stars ?? 0
        let forks = metadata?.forks ?? 0
        let stackBonus = min(2, stackItems.filter { ["framework", "runtime", "ai_integration"].contains($0.category) }.count / 3)
        let base: Int
        switch stars {
        case 10_000...:
            base = 9
        case 2_000..<10_000:
            base = 7
        case 500..<2_000:
            base = 5
        case 100..<500:
            base = 3
        default:
            base = 1
        }
        return min(10, base + min(2, forks / 500) + stackBonus)
    }

    private static func clampScore(_ value: Int) -> Int {
        min(10, max(0, value))
    }

    private static func throwIfCancelled(jobID: String, database: IntelligenceDatabase) throws {
        if try database.isIngestionJobCancelled(id: jobID) {
            throw RepositoryAIAnalysisError.cancelled
        }
    }

    private static func generateRelationshipsIfPossible(repository: RepositoryRecord,
                                                        database: IntelligenceDatabase) async {
        do {
            _ = try await GraphRelationshipService.generateRelationships(repository: repository, database: database)
        } catch {
            #if DEBUG
            print("[reshelf] Relationship generation failed for \(repository.fullName): \(error)")
            #endif
        }
    }
}

private extension String {
    func trimmedLimited(to limit: Int) -> String {
        String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

private extension Array where Element == String {
    func normalizedStrings(limit: Int) -> [String] {
        Array(map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(limit))
    }
}
