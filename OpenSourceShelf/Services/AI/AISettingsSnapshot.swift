import Foundation

/// UserDefaults + Keychain snapshot for background services without a SwiftData context.
enum AISettingsSnapshot {
    static let preferredProviderKey = "reshelf.preferredAIProvider"
    static let openAIEnabledKey = "reshelf.openAIEnabled"
    static let openAIModelKey = "reshelf.openAISelectedModel"
    static let anthropicEnabledKey = "reshelf.anthropicEnabled"
    static let anthropicModelKey = "reshelf.anthropicSelectedModel"
    static let geminiEnabledKey = "reshelf.geminiEnabled"
    static let geminiModelKey = "reshelf.geminiSelectedModel"
    static let githubCopilotEnabledKey = "reshelf.githubCopilotEnabled"
    static let githubCopilotModelKey = "reshelf.githubCopilotSelectedModel"

    static func sync(from settings: AppSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.preferredAIProviderRaw, forKey: preferredProviderKey)
        defaults.set(settings.ollamaEnabled, forKey: "reshelf.ollamaEnabled")
        defaults.set(settings.ollamaBaseURL, forKey: "reshelf.ollamaBaseURL")
        defaults.set(settings.ollamaSelectedModel, forKey: "reshelf.ollamaSelectedModel")
        defaults.set(settings.openAIEnabled, forKey: openAIEnabledKey)
        defaults.set(settings.openAISelectedModel, forKey: openAIModelKey)
        defaults.set(settings.anthropicEnabled, forKey: anthropicEnabledKey)
        defaults.set(settings.anthropicSelectedModel, forKey: anthropicModelKey)
        defaults.set(settings.geminiEnabled, forKey: geminiEnabledKey)
        defaults.set(settings.geminiSelectedModel, forKey: geminiModelKey)
        defaults.set(settings.githubCopilotEnabled, forKey: githubCopilotEnabledKey)
        defaults.set(settings.githubCopilotSelectedModel, forKey: githubCopilotModelKey)
    }

    static func preferredProvider() -> AIProviderKind {
        let raw = UserDefaults.standard.string(forKey: preferredProviderKey) ?? AIProviderKind.ollama.rawValue
        return AIProviderKind(rawValue: raw) ?? .ollama
    }

    static func isEnabled(_ provider: AIProviderKind) -> Bool {
        let defaults = UserDefaults.standard
        switch provider {
        case .ollama:
            return defaults.bool(forKey: "reshelf.ollamaEnabled")
                && !(defaults.string(forKey: "reshelf.ollamaSelectedModel") ?? "").isEmpty
        case .appleIntelligence:
            return false
        case .openAI:
            return defaults.bool(forKey: openAIEnabledKey)
        case .anthropic:
            return defaults.bool(forKey: anthropicEnabledKey)
        case .gemini:
            return defaults.bool(forKey: geminiEnabledKey)
        case .githubCopilot:
            return defaults.bool(forKey: githubCopilotEnabledKey)
        }
    }

    static func model(for provider: AIProviderKind) -> String {
        let defaults = UserDefaults.standard
        switch provider {
        case .ollama:
            return defaults.string(forKey: "reshelf.ollamaSelectedModel") ?? ""
        case .appleIntelligence:
            return ""
        case .openAI:
            return defaults.string(forKey: openAIModelKey) ?? AIProviderKind.openAI.defaultModel
        case .anthropic:
            return defaults.string(forKey: anthropicModelKey) ?? AIProviderKind.anthropic.defaultModel
        case .gemini:
            return defaults.string(forKey: geminiModelKey) ?? AIProviderKind.gemini.defaultModel
        case .githubCopilot:
            return defaults.string(forKey: githubCopilotModelKey) ?? AIProviderKind.githubCopilot.defaultModel
        }
    }

    static func isConfigured(_ provider: AIProviderKind) -> Bool {
        switch provider {
        case .ollama:
            return isEnabled(.ollama) && !(UserDefaults.standard.string(forKey: "reshelf.ollamaBaseURL") ?? "").isEmpty
        case .appleIntelligence:
            return false
        case .openAI, .anthropic, .gemini, .githubCopilot:
            return isEnabled(provider)
                && !model(for: provider).isEmpty
                && AIProviderCredentialStore.hasAPIKey(for: provider)
        }
    }

    static func resolvedProvider() -> AIProviderKind {
        let preferred = preferredProvider()
        if isConfigured(preferred) { return preferred }
        if isConfigured(.ollama) { return .ollama }
        for provider in AIProviderKind.allCases where isConfigured(provider) {
            return provider
        }
        return preferred
    }
}
