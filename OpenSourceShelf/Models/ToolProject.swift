import Foundation
import SwiftData

@Model
final class ToolProject {
    var id: UUID = UUID()
    var name: String = ""
    var shortDescription: String = ""
    var longDescription: String = ""
    var githubURL: String = ""
    var websiteURL: String = ""
    var category: String = ""
    var statusRaw: String = ProjectStatus.defaultStatus.rawValue
    var license: String = ""
    var stars: String = ""
    var tags: [String] = []
    var useCases: [String] = []
    var notes: String = ""
    /// Kika's own "why I saved this" — never written by AI or automation.
    var personalNote: String = ""
    var fitScore: Int = 0
    var addedDate: Date = Date()
    var lastCheckedDate: Date?
    /// When the *upstream project* last changed — GitHub's `pushed_at`, or the
    /// clone's own last commit date when it's on disk. Distinct from
    /// `lastCheckedDate` (when *you* last looked) and `addedDate` (when you
    /// shelved it). Optional because older rows predate the field and only fill
    /// in on capture, refresh, or backfill.
    var lastUpdatedDate: Date?

    var isLocalFirst: Bool = false
    var isSelfHosted: Bool = false
    @Attribute(.externalStorage) var iconData: Data?

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .collector }
        set { statusRaw = newValue.rawValue }
    }

    init(name: String = "",
         shortDescription: String = "",
         longDescription: String = "",
         githubURL: String = "",
         websiteURL: String = "",
         category: String = "",
         status: ProjectStatus = .collector,
         license: String = "",
         stars: String = "",
         tags: [String] = [],
         useCases: [String] = [],
         notes: String = "",
         personalNote: String = "",
         fitScore: Int = 0,
         addedDate: Date = Date(),
         lastUpdatedDate: Date? = nil,
         isLocalFirst: Bool = false,
         isSelfHosted: Bool = false) {
        self.id = UUID()
        self.name = name
        self.shortDescription = shortDescription
        self.longDescription = longDescription
        self.githubURL = githubURL
        self.websiteURL = websiteURL
        self.category = category
        self.statusRaw = status.rawValue
        self.license = license
        self.stars = stars
        self.tags = tags
        self.useCases = useCases
        self.notes = notes
        self.personalNote = personalNote
        self.fitScore = fitScore
        self.addedDate = addedDate
        self.lastUpdatedDate = lastUpdatedDate
        self.isLocalFirst = isLocalFirst
        self.isSelfHosted = isSelfHosted
    }

    func matchesSearch(_ query: String) -> Bool {
        let q = query.lowercased()
        return name.lowercased().contains(q)
            || shortDescription.lowercased().contains(q)
            || longDescription.lowercased().contains(q)
            || category.lowercased().contains(q)
            || tags.contains(where: { $0.lowercased().contains(q) })
            || notes.lowercased().contains(q)
            || personalNote.lowercased().contains(q)
            || useCases.contains(where: { $0.lowercased().contains(q) })
    }
}
