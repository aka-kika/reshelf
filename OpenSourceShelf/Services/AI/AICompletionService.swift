import Foundation

/// Routes text-generation prompts to the user's preferred configured provider.
enum AICompletionService {
    static func generate(prompt: String, settings: AppSettings) async -> String {
        let provider = resolvedProvider(settings: settings)

        switch provider {
        case .ollama:
            guard settings.ollamaEnabled, !settings.ollamaSelectedModel.isEmpty else {
                return configurationHint(settings: settings)
            }
            let baseURL = settings.ollamaBaseURL
            guard await OllamaService.testConnection(baseURL: baseURL) else {
                return "⚠️ Could not reach Ollama at \(baseURL)."
            }
            return await OllamaService.generateCompletion(baseURL: baseURL,
                                                          model: settings.ollamaSelectedModel,
                                                          prompt: prompt)

        case .appleIntelligence:
            guard settings.appleIntelligenceEnabled else {
                return configurationHint(settings: settings)
            }
            do {
                return try await AppleIntelligenceService.generateText(prompt: prompt)
            } catch {
                return "⚠️ Apple Intelligence: \(error.localizedDescription)"
            }

        case .openAI, .anthropic, .gemini, .githubCopilot:
            // Cloud providers were removed in 1.7.0 — reshelf generates on-device
            // or against your own Ollama, and nowhere else. The enum cases remain
            // only because `AppSettings` is a SwiftData model whose stored columns
            // default from them; dropping them would force a schema migration for
            // no user-visible gain.
            return configurationHint(settings: settings)
        }
    }

    static func resolvedProvider(settings: AppSettings) -> AIProviderKind {
        if settings.isConfigured(settings.preferredAIProvider) {
            return settings.preferredAIProvider
        }
        if settings.isConfigured(.ollama) {
            return .ollama
        }
        return settings.configuredAIProviders.first ?? settings.preferredAIProvider
    }

    private static func configurationHint(settings: AppSettings) -> String {
        if settings.configuredAIProviders.isEmpty {
            return "⚠️ Enable a provider and add credentials in Settings → AI Providers."
        }
        return "⚠️ Your preferred provider isn’t ready. Check Settings → AI Providers."
    }

}
