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
    /// The human-written "why I saved this". Optional because exports written
    /// before this field existed have no key for it — decoding those must not
    /// fail, and importing one must not blank out a note already on the project.
    var personalNote: String?
    var fitScore: Int
    var addedDate: Date
    var lastCheckedDate: Date?
    /// Optional for the same reason as `personalNote`: exports written
    /// before the field existed have no key for it.
    var lastUpdatedDate: Date?
    var isLocalFirst: Bool
    var isSelfHosted: Bool
    /// The folder this project was in on the exporting machine. Not applied
    /// directly on import — ids diverge between machines, so
    /// `CatalogImportService` remaps it against the local folder table.
    var folderID: String?

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
        personalNote = p.personalNote
        fitScore = p.fitScore
        addedDate = p.addedDate
        lastCheckedDate = p.lastCheckedDate
        lastUpdatedDate = p.lastUpdatedDate
        isLocalFirst = p.isLocalFirst
        isSelfHosted = p.isSelfHosted
        folderID = p.folderID?.uuidString
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
            personalNote: personalNote ?? "",
            fitScore: fitScore,
            addedDate: addedDate,
            lastUpdatedDate: lastUpdatedDate,
            isLocalFirst: isLocalFirst,
            isSelfHosted: isSelfHosted
        )
        if let uuid = UUID(uuidString: id) { project.id = uuid }
        project.lastCheckedDate = lastCheckedDate
        return project
    }

    /// Overwrites an existing project with this row's values — used when an
    /// import is told to update projects the catalog already has. Deliberately
    /// leaves `id` and `iconData` alone: the local identity and the cached icon
    /// aren't part of the exported snapshot, and clobbering them would churn
    /// selection state and drop artwork the file can't restore.
    func apply(to project: ToolProject) {
        project.name = name
        project.shortDescription = shortDescription
        project.longDescription = longDescription
        project.githubURL = githubURL
        project.websiteURL = websiteURL
        project.category = category
        project.status = ProjectStatus(rawValue: status) ?? project.status
        project.license = license
        project.stars = stars
        project.tags = tags
        project.useCases = useCases
        project.notes = notes
        // Only when the file actually carries one — an older export with no
        // personalNote key must not erase a note written on this machine.
        if let personalNote { project.personalNote = personalNote }
        project.fitScore = fitScore
        project.addedDate = addedDate
        project.lastCheckedDate = lastCheckedDate
        if let lastUpdatedDate { project.lastUpdatedDate = lastUpdatedDate }
        project.isLocalFirst = isLocalFirst
        project.isSelfHosted = isSelfHosted
    }
}

/// One folder in an export. Travels with the catalog so the grouping survives
/// the trip to another machine — the gap `personalNote` and `lastUpdatedDate`
/// each had to be fixed for after the fact.
struct CatalogFolderDTO: Codable {
    var id: String
    var name: String
    var createdAt: Date
    var sortIndex: Int

    init(_ f: CatalogFolder) {
        id = f.id.uuidString
        name = f.name
        createdAt = f.createdAt
        sortIndex = f.sortIndex
    }
}

struct CatalogSnapshotDTO: Codable {
    var exportedAt: Date
    var app: String
    var version: Int
    var projectCount: Int
    var projects: [CatalogProjectDTO]
    /// Optional so exports written before folders existed still decode.
    var folders: [CatalogFolderDTO]?
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
    static func encode(_ projects: [ToolProject], folders: [CatalogFolder] = []) throws -> Data {
        let payload = CatalogSnapshotDTO(
            exportedAt: Date(),
            app: "reshelf",
            version: 1,
            projectCount: projects.count,
            projects: projects.map(CatalogProjectDTO.init),
            folders: folders.isEmpty ? nil : folders.map(CatalogFolderDTO.init)
        )
        return try makeEncoder().encode(payload)
    }

    /// Decodes a snapshot/export JSON back into project rows.
    static func decode(_ data: Data) throws -> [CatalogProjectDTO] {
        try makeDecoder().decode(CatalogSnapshotDTO.self, from: data).projects
    }

    /// The folders in a snapshot/export. Empty for files written before folders
    /// existed.
    static func decodeFolders(_ data: Data) throws -> [CatalogFolderDTO] {
        try makeDecoder().decode(CatalogSnapshotDTO.self, from: data).folders ?? []
    }

    /// Presents a save panel and writes the catalog JSON. Shows an alert on failure.
    /// Must be called on the main thread (it drives AppKit panels).
    @MainActor
    static func presentExportPanel(projects: [ToolProject], folders: [CatalogFolder] = []) {
        let panel = NSSavePanel()
        panel.title = "Export Catalog"
        panel.message = "Save your reshelf catalog as JSON."
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultFilename()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try encode(projects, folders: folders)
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
