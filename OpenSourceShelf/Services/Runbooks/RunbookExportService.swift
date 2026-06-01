import AppKit
import Foundation
import UniformTypeIdentifiers

enum RunbookExportService {
    /// Written next to a local clone when the user chooses Save to Clone Folder.
    static let cloneFolderFilename = "RESHELF-RUNBOOK.md"

    static func copyToPasteboard(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    static func defaultFilename(for repository: RepositoryRecord, generatedAt: String) -> String {
        let slug = slugComponent(from: repository.name.isEmpty ? repository.fullName : repository.name)
        let date = exportDateStamp(from: generatedAt)
        return "runbook-\(slug)-\(date).md"
    }

    @discardableResult
    static func saveMarkdown(_ text: String, suggestedFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Runbook"
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func cloneFolderExportURL(clonePath: String) -> URL {
        URL(fileURLWithPath: clonePath, isDirectory: true).appendingPathComponent(cloneFolderFilename)
    }

    @discardableResult
    static func saveMarkdownToCloneFolder(_ text: String, clonePath: String) throws -> URL {
        guard !clonePath.isEmpty else {
            throw RunbookCloneExportError.missingClonePath
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: clonePath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RunbookCloneExportError.clonePathNotFound
        }

        let url = cloneFolderExportURL(clonePath: clonePath)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            throw RunbookCloneExportError.writeFailed(error.localizedDescription)
        }
    }

    static func slugComponent(from name: String) -> String {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        let lowered = base.lowercased()
        let allowed = lowered.map { char -> Character in
            char.isLetter || char.isNumber ? char : "-"
        }
        return String(allowed)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func exportDateStamp(from iso: String) -> String {
        if iso.count >= 10 {
            return String(iso.prefix(10))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

enum RunbookCloneExportError: LocalizedError {
    case missingClonePath
    case clonePathNotFound
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingClonePath:
            return "Clone this repository locally before saving a runbook beside it."
        case .clonePathNotFound:
            return "The clone folder no longer exists on disk."
        case let .writeFailed(message):
            return message
        }
    }
}
