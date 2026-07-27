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

    /// Background-safe routing using UserDefaults + Keychain (no SwiftData context).
    static func generateFromStoredPreferences(prompt: String) async -> (text: String, provider: AIProviderKind?) {
        let provider = AISettingsSnapshot.resolvedProvider()
        guard AISettingsSnapshot.isConfigured(provider) else {
            return (configurationHintFromSnapshot(), nil)
        }

        switch provider {
        case .ollama:
            let baseURL = UserDefaults.standard.string(forKey: "reshelf.ollamaBaseURL") ?? "http://localhost:11434"
            let model = AISettingsSnapshot.model(for: .ollama)
            guard await OllamaService.testConnection(baseURL: baseURL) else {
                return ("⚠️ Could not reach Ollama at \(baseURL).", nil)
            }
            let text = await OllamaService.generateCompletion(baseURL: baseURL, model: model, prompt: prompt)
            return (text, .ollama)

        case .appleIntelligence:
            do {
                let text = try await AppleIntelligenceService.generateText(prompt: prompt)
                return (text, .appleIntelligence)
            } catch {
                return ("⚠️ Apple Intelligence: \(error.localizedDescription)", nil)
            }

        case .openAI, .anthropic, .gemini, .githubCopilot:
            // See `generate(prompt:settings:)` — no cloud path exists any more.
            return (configurationHintFromSnapshot(), nil)
        }
    }

    private static func configurationHintFromSnapshot() -> String {
        if AIProviderKind.allCases.contains(where: { AISettingsSnapshot.isConfigured($0) }) {
            return "⚠️ Your preferred provider isn’t ready. Check Settings → AI Providers."
        }
        return "⚠️ Enable a provider and add credentials in Settings → AI Providers."
    }
}
