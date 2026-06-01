import Foundation
import AppKit
import UniformTypeIdentifiers

/// Flat, stable JSON shape for one project. Decoupled from the SwiftData model
/// so future schema changes don't silently alter the format. Shared by manual
/// JSON export *and* the automatic backups, so a backup is a valid export and
/// vice-versa.
struct CatalogProjectDTO: Codable {
    var id: String
    var name: String
    var shortDescription: String
    var longDescription: String
    var githubURL: String
    var websiteURL: String
    var category: String
    var status: String
    var license: String
    var stars: String
    var tags: [String]
    var useCases: [String]
    var notes: String
    var fitScore: Int
    var addedDate: Date
    var lastCheckedDate: Date?
    var isLocalFirst: Bool
    var isSelfHosted: Bool

    init(_ p: ToolProject) {
        id = p.id.uuidString
        name = p.name
        shortDescription = p.shortDescription
        longDescription = p.longDescription
        githubURL = p.githubURL
        websiteURL = p.websiteURL
        category = p.category
        status = p.status.rawValue
        license = p.license
        stars = p.stars
        tags = p.tags
        useCases = p.useCases
        notes = p.notes
        fitScore = p.fitScore
        addedDate = p.addedDate
        lastCheckedDate = p.lastCheckedDate
        isLocalFirst = p.isLocalFirst
        isSelfHosted = p.isSelfHosted
    }

    /// Rebuilds a `ToolProject` from a snapshot row (for restore/import).
    func makeToolProject() -> ToolProject {
        let project = ToolProject(
            name: name,
            shortDescription: shortDescription,
            longDescription: longDescription,
            githubURL: githubURL,
            websiteURL: websiteURL,
            category: category,
            status: ProjectStatus(rawValue: status) ?? .collector,
            license: license,
            stars: stars,
            tags: tags,
            useCases: useCases,
            notes: notes,
            fitScore: fitScore,
            addedDate: addedDate,
            isLocalFirst: isLocalFirst,
            isSelfHosted: isSelfHosted
        )
        if let uuid = UUID(uuidString: id) { project.id = uuid }
        project.lastCheckedDate = lastCheckedDate
        return project
    }
}

struct CatalogSnapshotDTO: Codable {
    var exportedAt: Date
    var app: String
    var version: Int
    var projectCount: Int
    var projects: [CatalogProjectDTO]
}

/// Exports the catalog (`ToolProject`s) to a portable JSON file the user picks
/// via a save panel. Binary icon data is intentionally omitted — the export is a
/// human-readable, re-importable snapshot of the catalog's metadata.
enum CatalogExportService {

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Encodes the given projects to pretty-printed, ISO-8601-dated JSON.
    static func encode(_ projects: [ToolProject]) throws -> Data {
        let payload = CatalogSnapshotDTO(
            exportedAt: Date(),
            app: "reshelf",
            version: 1,
            projectCount: projects.count,
            projects: projects.map(CatalogProjectDTO.init)
        )
        return try makeEncoder().encode(payload)
    }

    /// Decodes a snapshot/export JSON back into project rows.
    static func decode(_ data: Data) throws -> [CatalogProjectDTO] {
        try makeDecoder().decode(CatalogSnapshotDTO.self, from: data).projects
    }

    /// Presents a save panel and writes the catalog JSON. Shows an alert on failure.
    /// Must be called on the main thread (it drives AppKit panels).
    @MainActor
    static func presentExportPanel(projects: [ToolProject]) {
        let panel = NSSavePanel()
        panel.title = "Export Catalog"
        panel.message = "Save your reshelf catalog as JSON."
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultFilename()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try encode(projects)
            try data.write(to: url, options: .atomic)
        } catch {
            presentFailureAlert(error)
        }
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "reshelf-catalog-\(formatter.string(from: Date())).json"
    }

    @MainActor
    private static func presentFailureAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Export Catalog"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
