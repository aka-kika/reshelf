import Foundation
import SwiftData

/// Inspector sections the user can show/hide and reorder.
enum InspectorSection: String, CaseIterable, Identifiable, Codable {
    case useCases = "useCases"
    case tags = "tags"
    case notes = "notes"
    case personalNote = "personalNote"
    case personalFit = "personalFit"
    case github = "github"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useCases: "Use Cases"
        case .tags: "Tags"
        case .notes: "Notes"
        case .personalNote: "Why I Saved This"
        case .personalFit: "Personal Fit"
        // Stars/license live in the fixed Metadata section; this toggles the
        // extras GitHub adds on top (topics, richer description).
        case .github: "GitHub Topics"
        }
    }

    var icon: String {
        switch self {
        case .useCases: "list.bullet"
        case .tags: "tag"
        case .notes: "note.text"
        case .personalNote: "quote.bubble"
        case .personalFit: "star"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }

}

@Model
final class AppSettings {
    var ollamaEnabled: Bool = true
    var ollamaBaseURL: String = "http://localhost:11434"
    var ollamaSelectedModel: String = ""
    var ollamaEmbeddingModel: String = "nomic-embed-text"
    var semanticSearchEnabled: Bool = true
    var appleIntelligenceEnabled: Bool = false
    var autoGenerateRunbookAfterIntelligence: Bool = false

    /// Quick Capture, runbook polish, and other text suggestions.
    var preferredAIProviderRaw: String = AIProviderKind.ollama.rawValue

    var openAIEnabled: Bool = false
    var openAISelectedModel: String = AIProviderKind.openAI.defaultModel
    var anthropicEnabled: Bool = false
    var anthropicSelectedModel: String = AIProviderKind.anthropic.defaultModel
    var geminiEnabled: Bool = false
    var geminiSelectedModel: String = AIProviderKind.gemini.defaultModel
    var githubCopilotEnabled: Bool = false
    var githubCopilotSelectedModel: String = AIProviderKind.githubCopilot.defaultModel

    // Inspector section visibility (default: show all)
    var showInspectorUseCases: Bool = true
    var showInspectorTags: Bool = true
    var showInspectorNotes: Bool = true
    var showInspectorPersonalNote: Bool = true
    var showInspectorPersonalFit: Bool = true
    var showInspectorGitHub: Bool = true
    var showInspectorStack: Bool = true
    var showInspectorRelationships: Bool = true
    var showInspectorRecommendations: Bool = true

    /// JSON-encoded array of InspectorSection raw values for custom ordering.
    /// Empty string means default order (InspectorSection.allCases).
    var inspectorSectionOrderData: String = ""

    static let autoGenerateRunbookKey = "reshelf.autoGenerateRunbookAfterIntelligence"

    // MARK: - Inspector section order helpers

    /// The ordered list of inspector sections. Falls back to default if no custom order is stored.
    var inspectorSectionOrder: [InspectorSection] {
        get {
            guard !inspectorSectionOrderData.isEmpty,
                  let data = inspectorSectionOrderData.data(using: .utf8),
                  let rawValues = try? JSONDecoder().decode([String].self, from: data) else {
                return InspectorSection.allCases
            }
            let decoded = rawValues.compactMap { InspectorSection(rawValue: $0) }
            // If there are newly-added sections not in the stored order, append them
            let missing = InspectorSection.allCases.filter { !decoded.contains($0) }
            return decoded + missing
        }
        set {
            let rawValues = newValue.map(\.rawValue)
            if let data = try? JSONEncoder().encode(rawValues),
               let json = String(data: data, encoding: .utf8) {
                inspectorSectionOrderData = json
            }
        }
    }

    /// Whether a given section is visible, reading the per-section Bool flags.
    func isVisible(_ section: InspectorSection) -> Bool {
        switch section {
        case .useCases: return showInspectorUseCases
        case .tags: return showInspectorTags
        case .notes: return showInspectorNotes
        case .personalNote: return showInspectorPersonalNote
        case .personalFit: return showInspectorPersonalFit
        case .github: return showInspectorGitHub
        }
    }

    /// Toggle visibility for a given section.
    func setVisible(_ section: InspectorSection, _ value: Bool) {
        switch section {
        case .useCases: showInspectorUseCases = value
        case .tags: showInspectorTags = value
        case .notes: showInspectorNotes = value
        case .personalNote: showInspectorPersonalNote = value
        case .personalFit: showInspectorPersonalFit = value
        case .github: showInspectorGitHub = value
        }
    }

    // Singleton pattern — there should only ever be one settings object
    static func current(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    init() {}
}
