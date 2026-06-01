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
            return "⚠️ Apple Intelligence is enabled in Settings but not wired to text suggestions yet. Choose Ollama or a cloud provider for now."

        case .openAI, .anthropic, .gemini, .githubCopilot:
            guard settings.isEnabled(provider) else {
                return configurationHint(settings: settings)
            }
            guard let apiKey = AIProviderCredentialStore.loadAPIKey(for: provider) else {
                return "⚠️ Add an API key for \(provider.displayName) in Settings."
            }
            let model = settings.selectedModel(for: provider)
            guard !model.isEmpty else {
                return "⚠️ Choose a model for \(provider.displayName) in Settings."
            }
            do {
                return try await CloudAICompletionService.generate(provider: provider,
                                                                   apiKey: apiKey,
                                                                   model: model,
                                                                   prompt: prompt)
            } catch {
                return "⚠️ \(provider.displayName) error: \(error.localizedDescription)"
            }
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
            return ("⚠️ Apple Intelligence is not wired to text suggestions yet.", nil)

        case .openAI, .anthropic, .gemini, .githubCopilot:
            guard AISettingsSnapshot.isEnabled(provider),
                  let apiKey = AIProviderCredentialStore.loadAPIKey(for: provider) else {
                return (configurationHintFromSnapshot(), nil)
            }
            let model = AISettingsSnapshot.model(for: provider)
            do {
                let text = try await CloudAICompletionService.generate(provider: provider,
                                                                         apiKey: apiKey,
                                                                         model: model,
                                                                         prompt: prompt,
                                                                         maxTokens: 2048,
                                                                         temperature: 0.4)
                return (text, provider)
            } catch {
                return ("⚠️ \(provider.displayName) error: \(error.localizedDescription)", nil)
            }
        }
    }

    private static func configurationHintFromSnapshot() -> String {
        if AIProviderKind.allCases.contains(where: { AISettingsSnapshot.isConfigured($0) }) {
            return "⚠️ Your preferred provider isn’t ready. Check Settings → AI Providers."
        }
        return "⚠️ Enable a provider and add credentials in Settings → AI Providers."
    }
}
