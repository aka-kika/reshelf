import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device text generation via Apple's FoundationModels framework (Apple Intelligence).
/// Safe to reference on any macOS version; generation requires macOS 26+ with
/// Apple Intelligence enabled and the on-device model downloaded.
enum AppleIntelligenceService {
    /// Recorded as the model name in analysis cache keys and insight records.
    static let modelIdentifier = "apple-foundation-on-device"

    enum Availability: Equatable {
        case available
        case osTooOld
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case frameworkMissing
        case unavailable(String)

        var isAvailable: Bool { self == .available }

        var label: String {
            switch self {
            case .available:
                "Ready — on-device model available"
            case .osTooOld:
                "Requires macOS 26 or later"
            case .deviceNotEligible:
                "This Mac does not support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                "Turn on Apple Intelligence in System Settings"
            case .modelNotReady:
                "Model is downloading — try again shortly"
            case .frameworkMissing:
                "This build does not include FoundationModels support"
            case .unavailable(let reason):
                "Unavailable: \(reason)"
            }
        }
    }

    enum GenerationFailure: LocalizedError {
        case unavailable(Availability)
        case contextWindowExceeded

        var errorDescription: String? {
            switch self {
            case .unavailable(let availability):
                return availability.label
            case .contextWindowExceeded:
                return "The evidence did not fit the on-device model's context window."
            }
        }
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .osTooOld }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .unavailable(String(describing: reason))
            }
        @unknown default:
            return .unavailable("Unknown availability state")
        }
        #else
        return .frameworkMissing
        #endif
    }

    /// Plain text completion for Quick Capture suggestions and runbook polish.
    static func generateText(prompt: String, instructions: String? = nil) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw GenerationFailure.unavailable(.osTooOld) }
        let status = availability
        guard status.isAvailable else { throw GenerationFailure.unavailable(status) }

        let session = instructions.map { LanguageModelSession(instructions: $0) }
            ?? LanguageModelSession()
        do {
            return try await session.respond(to: prompt).content
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
        #else
        throw GenerationFailure.unavailable(.frameworkMissing)
        #endif
    }

    /// Structured Quick Capture suggestions — the model fills the fields directly
    /// via guided generation, so results land in the capture form without parsing.
    struct CaptureSuggestion {
        var useCases: [String]
        var note: String
        var tags: [String]
        var isLocalFirst: Bool
        var isSelfHosted: Bool
    }

    static func suggestCapture(prompt: String) async throws -> CaptureSuggestion {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw GenerationFailure.unavailable(.osTooOld) }
        let status = availability
        guard status.isAvailable else { throw GenerationFailure.unavailable(status) }

        let session = LanguageModelSession(instructions: """
            You help catalog open source tools in a developer's personal shelf app. \
            Base every field only on the provided project facts. \
            Keep wording short, concrete, and practical.
            """)
        do {
            let generated = try await session.respond(to: prompt,
                                                      generating: CaptureSuggestionGeneration.self).content
            return CaptureSuggestion(useCases: generated.useCases,
                                     note: generated.note,
                                     tags: generated.tags,
                                     isLocalFirst: generated.isLocalFirst,
                                     isSelfHosted: generated.isSelfHosted)
        } catch let error as LanguageModelSession.GenerationError {
            throw mapGenerationError(error)
        }
        #else
        throw GenerationFailure.unavailable(.frameworkMissing)
        #endif
    }


    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> Error {
        if case .exceededContextWindowSize = error {
            return GenerationFailure.contextWindowExceeded
        }
        return error
    }
    #endif
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct CaptureSuggestionGeneration {
    @Guide(description: "3 to 5 practical ways a developer or maker would use this tool in real workflows, one short phrase each")
    var useCases: [String]
    @Guide(description: "One or two sentences on why this tool is worth keeping on the shelf")
    var note: String
    @Guide(description: "2 to 3 short lowercase tags that are not already in the existing tags")
    var tags: [String]
    @Guide(description: "True only if the tool runs locally or offline-first")
    var isLocalFirst: Bool
    @Guide(description: "True only if the tool is designed to be self-hosted")
    var isSelfHosted: Bool
}
#endif
