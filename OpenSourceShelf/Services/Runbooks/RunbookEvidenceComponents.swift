import Foundation

struct RunbookEvidenceComponents: Codable, Equatable {
    var repositoryID: String
    var commitSHA: String?
    var readmeHash: String?
    var manifestPaths: [String]
    var manifestTypes: [String]
    var stackLabels: [String]
    var aiGeneratedAt: String?
    var aiCacheKey: String?
    var promptVersion: String
    var modelName: String
    var dockerPresent: Bool
    var packageManagers: [String]

    static func from(evidence: RunbookEvidence,
                     promptVersion: String = RunbookCache.promptVersion,
                     modelName: String = RunbookCache.modelName) -> RunbookEvidenceComponents {
        let manifestTypes = Set(evidence.manifests.map(\.type))
        var packageManagers: [String] = []
        if manifestTypes.contains("package_json") {
            if manifestTypes.contains("pnpm_lock") || evidence.manifests.contains(where: { $0.path.contains("pnpm") }) {
                packageManagers.append("pnpm")
            } else if manifestTypes.contains("yarn_lock") {
                packageManagers.append("yarn")
            } else if manifestTypes.contains("bun_lock") {
                packageManagers.append("bun")
            } else {
                packageManagers.append("npm")
            }
        }

        return RunbookEvidenceComponents(
            repositoryID: evidence.repository.id,
            commitSHA: evidence.repository.latestCommitSHA,
            readmeHash: RunbookEvidenceCollector.readmeHash(from: evidence.readmeExcerpt),
            manifestPaths: evidence.manifests.map(\.path).sorted(),
            manifestTypes: evidence.manifests.map(\.type).sorted(),
            stackLabels: evidence.stackItems.map { "\($0.category):\($0.name)" }.sorted(),
            aiGeneratedAt: evidence.aiInsight?.generatedAt,
            aiCacheKey: evidence.aiInsight?.cacheKey,
            promptVersion: promptVersion,
            modelName: modelName,
            dockerPresent: manifestTypes.contains("dockerfile") || manifestTypes.contains("docker_compose"),
            packageManagers: packageManagers.sorted()
        )
    }

    func encodedJSON() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func decode(from json: String?) -> RunbookEvidenceComponents? {
        guard let json,
              let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(RunbookEvidenceComponents.self, from: data) else {
            return nil
        }
        return value
    }
}

struct RunbookEvidenceChange: Equatable, Identifiable {
    var id: String { message }
    var message: String
}

enum RunbookFreshnessState: Equatable {
    case neverGenerated
    case fresh
    case stale(changes: [RunbookEvidenceChange])
    case generatedWithOlderTemplate(changes: [RunbookEvidenceChange])

    var isStale: Bool {
        switch self {
        case .neverGenerated, .fresh:
            return false
        case .stale, .generatedWithOlderTemplate:
            return true
        }
    }

    var badgeTitle: String {
        switch self {
        case .neverGenerated:
            return "Never generated"
        case .fresh:
            return "Fresh"
        case .stale:
            return "Stale"
        case .generatedWithOlderTemplate:
            return "Older template"
        }
    }

    var summaryText: String? {
        switch self {
        case .neverGenerated:
            return nil
        case .fresh:
            return "Evidence matches the last generation."
        case .stale(let changes), .generatedWithOlderTemplate(let changes):
            return changes.map(\.message).joined(separator: " ")
        }
    }
}

enum RunbookFreshnessEvaluator {
    static func evaluate(runbook: RepositoryRunbookRecord?,
                         evidence: RunbookEvidence) -> RunbookFreshnessState {
        guard let runbook else { return .neverGenerated }

        let current = RunbookEvidenceComponents.from(evidence: evidence)
        let currentSignature = RunbookEvidenceCollector.computeEvidenceSignature(for: evidence)
        if runbook.evidenceSignature == currentSignature {
            return .fresh
        }

        let stored = RunbookEvidenceComponents.decode(from: runbook.evidenceComponentsJSON)
            ?? inferLegacyComponents(from: runbook)
        let changes = diff(stored: stored, current: current)

        if runbook.promptVersion != RunbookCache.promptVersion {
            var templateChanges = changes
            templateChanges.insert(RunbookEvidenceChange(message: "Runbook template changed since last generation."), at: 0)
            return .generatedWithOlderTemplate(changes: templateChanges)
        }

        return .stale(changes: changes)
    }

    static func diff(stored: RunbookEvidenceComponents,
                     current: RunbookEvidenceComponents) -> [RunbookEvidenceChange] {
        var changes: [RunbookEvidenceChange] = []

        if stored.commitSHA != current.commitSHA {
            let from = shortSHA(stored.commitSHA)
            let to = shortSHA(current.commitSHA)
            changes.append(RunbookEvidenceChange(message: "Repo HEAD changed from \(from) to \(to)."))
        }

        if stored.readmeHash != current.readmeHash {
            changes.append(RunbookEvidenceChange(message: "README changed since last generation."))
        }

        if stored.manifestPaths != current.manifestPaths || stored.manifestTypes != current.manifestTypes {
            let addedDocker = current.dockerPresent && !stored.dockerPresent
            if addedDocker {
                changes.append(RunbookEvidenceChange(message: "New Dockerfile or compose file detected."))
            } else {
                changes.append(RunbookEvidenceChange(message: "Manifest detections changed."))
            }
        }

        if stored.packageManagers != current.packageManagers {
            let from = stored.packageManagers.joined(separator: ", ").ifEmpty("unknown")
            let to = current.packageManagers.joined(separator: ", ").ifEmpty("unknown")
            changes.append(RunbookEvidenceChange(message: "Detected package manager changed from \(from) to \(to)."))
        }

        if stored.stackLabels != current.stackLabels {
            changes.append(RunbookEvidenceChange(message: "Stack detections changed."))
        }

        if stored.aiGeneratedAt != current.aiGeneratedAt || stored.aiCacheKey != current.aiCacheKey {
            changes.append(RunbookEvidenceChange(message: "AI insight changed since last generation."))
        }

        if changes.isEmpty {
            changes.append(RunbookEvidenceChange(message: "Evidence signature changed since last generation."))
        }

        return changes
    }

    private static func inferLegacyComponents(from runbook: RepositoryRunbookRecord) -> RunbookEvidenceComponents {
        RunbookEvidenceComponents(
            repositoryID: runbook.repositoryID,
            commitSHA: nil,
            readmeHash: nil,
            manifestPaths: [],
            manifestTypes: [],
            stackLabels: [],
            aiGeneratedAt: nil,
            aiCacheKey: nil,
            promptVersion: runbook.promptVersion ?? RunbookCache.promptVersion,
            modelName: runbook.modelName ?? RunbookCache.modelName,
            dockerPresent: false,
            packageManagers: []
        )
    }

    private static func shortSHA(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "unknown" }
        return String(value.prefix(7))
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
