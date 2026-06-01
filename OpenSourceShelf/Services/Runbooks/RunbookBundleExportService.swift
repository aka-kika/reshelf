import AppKit
import Foundation
import UniformTypeIdentifiers

struct RunbookExportBundlePayload: Codable {
    struct GenerationMetadata: Codable {
        var generatedAt: String
        var generatedBy: String
        var modelName: String?
        var promptVersion: String?
        var evidenceSignature: String
    }

    struct RunbookGraphEdgeExport: Codable {
        var relationshipType: String
        var targetLabel: String
        var confidence: Double
    }

    var runbookMarkdown: String
    var evidence: RunbookEvidenceComponents
    var repository: [String: String]
    var stack: [[String: String]]
    var scores: [String: Int]?
    var graphRelationships: [RunbookGraphEdgeExport]
    var generation: GenerationMetadata
    var exportedAt: String
}

enum RunbookBundleExportError: LocalizedError {
    case cancelled
    case writeFailed(String)
    case zipFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Export was cancelled."
        case let .writeFailed(message):
            return message
        case let .zipFailed(message):
            return message
        }
    }
}

enum RunbookBundleExportService {
    static func buildPayload(runbook: RepositoryRunbookRecord,
                             evidence: RunbookEvidence,
                             database: IntelligenceDatabase = .shared) throws -> RunbookExportBundlePayload {
        let components = RunbookEvidenceComponents.from(evidence: evidence)
        let relationships = try database.fetchGraphRelationships(repositoryID: evidence.repository.id)
        let score = evidence.repositoryScore

        return RunbookExportBundlePayload(
            runbookMarkdown: runbook.markdown,
            evidence: components,
            repository: [
                "id": evidence.repository.id,
                "fullName": evidence.repository.fullName,
                "githubURL": evidence.repository.githubURL,
                "latestCommitSHA": evidence.repository.latestCommitSHA ?? "",
                "clonePath": evidence.clonePath ?? ""
            ],
            stack: evidence.stackItems.map {
                [
                    "category": $0.category,
                    "name": $0.name,
                    "detectedAt": $0.detectedAt
                ]
            },
            scores: score.map {
                [
                    "setupComplexity": $0.setupComplexity,
                    "localFirstScore": $0.localFirstScore,
                    "experimentationPriority": $0.experimentationPriority,
                    "ecosystemInfluence": $0.ecosystemInfluence,
                    "personalRelevance": $0.personalRelevance
                ]
            },
            graphRelationships: relationships.prefix(40).map {
                RunbookExportBundlePayload.RunbookGraphEdgeExport(
                    relationshipType: $0.relationshipType,
                    targetLabel: $0.targetLabel,
                    confidence: $0.confidence
                )
            },
            generation: .init(
                generatedAt: runbook.updatedAt,
                generatedBy: runbook.generatedBy,
                modelName: runbook.modelName,
                promptVersion: runbook.promptVersion,
                evidenceSignature: runbook.evidenceSignature
            ),
            exportedAt: IntelligenceDatabase.iso8601String()
        )
    }

    static func defaultBundleFolderName(for repository: RepositoryRecord, exportedAt: String) -> String {
        let slug = RunbookExportService.slugComponent(from: repository.name.isEmpty ? repository.fullName : repository.name)
        let date = RunbookExportService.exportDateStamp(from: exportedAt)
        return "runbook-\(slug)-bundle-\(date)"
    }

    static func defaultZipFilename(for repository: RepositoryRecord, exportedAt: String) -> String {
        "\(defaultBundleFolderName(for: repository, exportedAt: exportedAt)).zip"
    }

    @discardableResult
    static func exportBundle(_ payload: RunbookExportBundlePayload,
                             suggestedFolderName: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Export Runbook Bundle"
        panel.message = "Choose a folder. reshelf will create runbook.md and evidence.json inside it."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.nameFieldStringValue = suggestedFolderName
        guard panel.runModal() == .OK, let baseURL = panel.url else { return nil }

        let folderURL = uniqueFolderURL(base: baseURL, name: suggestedFolderName)
        do {
            try writeBundleFiles(payload, to: folderURL)
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            return folderURL
        } catch {
            NSSound.beep()
            return nil
        }
    }

    @discardableResult
    static func exportBundleZip(_ payload: RunbookExportBundlePayload,
                                suggestedFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Runbook Bundle as ZIP"
        panel.message = "The archive will contain runbook.md and evidence.json."
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let zipURL = panel.url else { return nil }

        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("OpenSourceShelf-runbook-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
            try writeBundleFiles(payload, to: tempRoot)
            let entries = [
                RunbookZipArchiveWriter.Entry(path: "runbook.md",
                                              data: Data(payload.runbookMarkdown.utf8)),
                RunbookZipArchiveWriter.Entry(path: "evidence.json",
                                              data: try encodedEvidenceJSON(payload))
            ]
            try RunbookZipArchiveWriter.write(entries: entries, to: zipURL)
            NSWorkspace.shared.activateFileViewerSelecting([zipURL])
            return zipURL
        } catch let error as RunbookBundleExportError {
            NSSound.beep()
            presentExportError(error.localizedDescription)
            return nil
        } catch {
            NSSound.beep()
            presentExportError("Could not create ZIP archive: \(error.localizedDescription)")
            return nil
        }
    }

    static func writeBundleFiles(_ payload: RunbookExportBundlePayload, to folderURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        do {
            try payload.runbookMarkdown.write(to: folderURL.appendingPathComponent("runbook.md"),
                                                atomically: true,
                                                encoding: .utf8)
            try encodedEvidenceJSON(payload).write(to: folderURL.appendingPathComponent("evidence.json"))
        } catch {
            throw RunbookBundleExportError.writeFailed("Could not write bundle files: \(error.localizedDescription)")
        }
    }

    private static func encodedEvidenceJSON(_ payload: RunbookExportBundlePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private static func presentExportError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Runbook ZIP export failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func uniqueFolderURL(base: URL, name: String) -> URL {
        var candidate = base.appendingPathComponent(name, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = base.appendingPathComponent("\(name)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }
}
