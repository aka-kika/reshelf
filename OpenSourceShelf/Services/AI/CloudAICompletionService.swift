import Foundation

enum CloudAICompletionService {
    static func testConnection(provider: AIProviderKind, apiKey: String, model: String) async -> Result<Void, Error> {
        do {
            _ = try await generate(provider: provider,
                                   apiKey: apiKey,
                                   model: model.isEmpty ? provider.defaultModel : model,
                                   prompt: "Reply with exactly: ok",
                                   maxTokens: 16,
                                   temperature: 0)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func generate(provider: AIProviderKind,
                         apiKey: String,
                         model: String,
                         prompt: String,
                         maxTokens: Int = 512,
                         temperature: Double = 0.7) async throws -> String {
        switch provider {
        case .openAI:
            return try await openAIChat(apiKey: apiKey, model: model, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
        case .anthropic:
            return try await anthropicMessage(apiKey: apiKey, model: model, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
        case .gemini:
            return try await geminiGenerate(apiKey: apiKey, model: model, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
        case .githubCopilot:
            return try await githubModelsChat(apiKey: apiKey, model: model, prompt: prompt, maxTokens: maxTokens, temperature: temperature)
        case .ollama, .appleIntelligence:
            throw CloudAICompletionError.unsupportedProvider
        }
    }

    private static func openAIChat(apiKey: String,
                                   model: String,
                                   prompt: String,
                                   maxTokens: Int,
                                   temperature: Double) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        let data = try await postJSON(url: url,
                                      headers: ["Authorization": "Bearer \(apiKey)"],
                                      body: body)

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CloudAICompletionError.emptyResponse
        }
        return text
    }

    private static func anthropicMessage(apiKey: String,
                                         model: String,
                                         prompt: String,
                                         maxTokens: Int,
                                         temperature: Double) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        let data = try await postJSON(url: url,
                                      headers: [
                                        "x-api-key": apiKey,
                                        "anthropic-version": "2023-06-01"
                                      ],
                                      body: body)

        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CloudAICompletionError.emptyResponse }
        return text
    }

    private static func geminiGenerate(apiKey: String,
                                       model: String,
                                       prompt: String,
                                       maxTokens: Int,
                                       temperature: Double) async throws -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw CloudAICompletionError.invalidURL }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": temperature
            ]
        ]
        let data = try await postJSON(url: url, headers: [:], body: body)

        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.candidates
            .flatMap { $0.content.parts }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CloudAICompletionError.emptyResponse }
        return text
    }

    private static func githubModelsChat(apiKey: String,
                                         model: String,
                                         prompt: String,
                                         maxTokens: Int,
                                         temperature: Double) async throws -> String {
        let url = URL(string: "https://models.github.ai/inference/chat/completions")!
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        let data = try await postJSON(url: url,
                                      headers: [
                                        "Authorization": "Bearer \(apiKey)",
                                        "Accept": "application/vnd.github+json"
                                      ],
                                      body: body)

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw CloudAICompletionError.emptyResponse
        }
        return text
    }

    private static func postJSON(url: URL, headers: [String: String], body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAICompletionError.networkFailure
        }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw CloudAICompletionError.httpError(http.statusCode, snippet)
        }
        return data
    }
}

enum CloudAICompletionError: LocalizedError {
    case unsupportedProvider
    case invalidURL
    case networkFailure
    case emptyResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "That provider is not available for cloud completion."
        case .invalidURL:
            return "The provider URL is invalid."
        case .networkFailure:
            return "Network request failed."
        case .emptyResponse:
            return "The provider returned an empty response."
        case let .httpError(code, snippet):
            let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Provider returned HTTP \(code)."
            }
            return "Provider returned HTTP \(code): \(String(trimmed.prefix(180)))"
        }
    }
}
