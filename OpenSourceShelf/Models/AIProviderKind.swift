import Foundation

/// AI backends reshelf can use for Quick Capture suggestions, runbook polish, and analysis.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case ollama
    case appleIntelligence
    case openAI
    case anthropic
    case gemini
    case githubCopilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .appleIntelligence: "Apple Intelligence"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .githubCopilot: "GitHub Copilot"
        }
    }

    var subtitle: String {
        switch self {
        case .ollama: "Local open-source LLM server"
        case .appleIntelligence: "On-device language & image models"
        case .openAI: "GPT models via OpenAI API"
        case .anthropic: "Claude models via Anthropic API"
        case .gemini: "Gemini models via Google AI API"
        case .githubCopilot: "GitHub Models / Copilot-capable endpoints"
        }
    }

    var systemImage: String {
        switch self {
        case .ollama: "tortoise"
        case .appleIntelligence: "apple.intelligence"
        case .openAI: "sparkles"
        case .anthropic: "brain.head.profile"
        case .gemini: "diamond"
        case .githubCopilot: "chevron.left.forwardslash.chevron.right"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .appleIntelligence: false
        case .openAI, .anthropic, .gemini, .githubCopilot: true
        }
    }

    var isLocalFirst: Bool {
        switch self {
        case .ollama, .appleIntelligence: true
        default: false
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: ""
        case .appleIntelligence: ""
        case .openAI: "gpt-4.1-mini"
        case .anthropic: "claude-sonnet-4-20250514"
        case .gemini: "gemini-2.0-flash"
        case .githubCopilot: "openai/gpt-4.1"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .ollama: []
        case .appleIntelligence: []
        case .openAI: ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini", "gpt-4o"]
        case .anthropic: ["claude-sonnet-4-20250514", "claude-3-5-haiku-20241022", "claude-3-5-sonnet-20241022"]
        case .gemini: ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-pro"]
        case .githubCopilot: ["openai/gpt-4.1", "openai/gpt-4o", "meta/llama-3.3-70b-instruct"]
        }
    }

    var apiKeyHelp: String {
        switch self {
        case .openAI:
            return "Create an API key at platform.openai.com. Stored securely in the macOS Keychain."
        case .anthropic:
            return "Create an API key at console.anthropic.com. Stored securely in the macOS Keychain."
        case .gemini:
            return "Create an API key in Google AI Studio. Stored securely in the macOS Keychain."
        case .githubCopilot:
            return "Use a GitHub personal access token with models access. Stored securely in the macOS Keychain."
        default:
            return ""
        }
    }

    /// Providers shown in the “Use for AI suggestions” picker.
    static var selectableProviders: [AIProviderKind] {
        allCases.filter { $0 != .appleIntelligence }
    }
}

extension AppSettings {
    var preferredAIProvider: AIProviderKind {
        get { AIProviderKind(rawValue: preferredAIProviderRaw) ?? .ollama }
        set { preferredAIProviderRaw = newValue.rawValue }
    }

    func isEnabled(_ provider: AIProviderKind) -> Bool {
        switch provider {
        case .ollama: ollamaEnabled
        case .appleIntelligence: appleIntelligenceEnabled
        case .openAI: openAIEnabled
        case .anthropic: anthropicEnabled
        case .gemini: geminiEnabled
        case .githubCopilot: githubCopilotEnabled
        }
    }

    func setEnabled(_ provider: AIProviderKind, _ value: Bool) {
        switch provider {
        case .ollama: ollamaEnabled = value
        case .appleIntelligence: appleIntelligenceEnabled = value
        case .openAI: openAIEnabled = value
        case .anthropic: anthropicEnabled = value
        case .gemini: geminiEnabled = value
        case .githubCopilot: githubCopilotEnabled = value
        }
    }

    func selectedModel(for provider: AIProviderKind) -> String {
        switch provider {
        case .ollama: ollamaSelectedModel
        case .appleIntelligence: ""
        case .openAI: openAISelectedModel
        case .anthropic: anthropicSelectedModel
        case .gemini: geminiSelectedModel
        case .githubCopilot: githubCopilotSelectedModel
        }
    }

    func setSelectedModel(_ provider: AIProviderKind, _ model: String) {
        switch provider {
        case .ollama: ollamaSelectedModel = model
        case .appleIntelligence: break
        case .openAI: openAISelectedModel = model
        case .anthropic: anthropicSelectedModel = model
        case .gemini: geminiSelectedModel = model
        case .githubCopilot: githubCopilotSelectedModel = model
        }
    }

    func isConfigured(_ provider: AIProviderKind) -> Bool {
        switch provider {
        case .ollama:
            return ollamaEnabled && !ollamaSelectedModel.isEmpty
        case .appleIntelligence:
            return appleIntelligenceEnabled
        case .openAI, .anthropic, .gemini, .githubCopilot:
            guard isEnabled(provider) else { return false }
            let model = selectedModel(for: provider)
            return !model.isEmpty && AIProviderCredentialStore.hasAPIKey(for: provider)
        }
    }

    var configuredAIProviders: [AIProviderKind] {
        AIProviderKind.allCases.filter { isConfigured($0) }
    }
}
