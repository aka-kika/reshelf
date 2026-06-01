import Foundation

struct OllamaModel: Identifiable, Codable {
    var id: String { name }
    let name: String
    let size: Int64?
    let modifiedAt: String?
    let digest: String?

    var sizeFormatted: String {
        guard let size else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    enum CodingKeys: String, CodingKey {
        case name, size
        case modifiedAt = "modified_at"
        case digest
    }
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

enum OllamaService {
    static func fetchModels(baseURL: String) async throws -> [OllamaModel] {
        let url = URL(string: "\(baseURL)/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.connectionFailed
        }

        let decoded = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return decoded.models
    }

    static func testConnection(baseURL: String) async -> Bool {
        do {
            let url = URL(string: "\(baseURL)/api/tags")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    static func generateCompletion(baseURL: String, model: String, prompt: String) async -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            return "Invalid URL"
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.7, "num_predict": 512]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return "⚠️ Ollama returned an error."
            }
            struct GenResponse: Codable { let response: String }
            let decoded = try JSONDecoder().decode(GenResponse.self, from: data)
            return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "⚠️ Could not reach Ollama. Make sure it's running at \(baseURL)."
        }
    }

    static func generateJSONCompletion(baseURL: String,
                                       model: String,
                                       prompt: String,
                                       timeout: TimeInterval = 45,
                                       retries: Int = 1) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }

        var lastError: Error?
        for attempt in 0...retries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = timeout
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model,
                    "prompt": prompt,
                    "stream": false,
                    "format": "json",
                    "options": [
                        "temperature": 0.1,
                        "num_predict": 700
                    ]
                ])

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OllamaError.connectionFailed
                }
                guard httpResponse.statusCode == 200 else {
                    throw OllamaError.generationFailed("Ollama returned HTTP \(httpResponse.statusCode).")
                }

                struct GenResponse: Codable { let response: String }
                let decoded = try JSONDecoder().decode(GenResponse.self, from: data)
                let output = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else {
                    throw OllamaError.generationFailed("Ollama returned an empty response.")
                }
                return output
            } catch {
                lastError = error
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: 750_000_000)
                }
            }
        }

        throw lastError ?? OllamaError.connectionFailed
    }

    static func generateEmbedding(baseURL: String,
                                  model: String,
                                  text: String,
                                  timeout: TimeInterval = 30) async throws -> [Float] {
        guard let url = URL(string: "\(baseURL)/api/embeddings") else {
            throw OllamaError.invalidURL
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OllamaError.generationFailed("Cannot embed empty text.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": trimmed
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.connectionFailed
        }
        guard httpResponse.statusCode == 200 else {
            throw OllamaError.generationFailed("Ollama embeddings returned HTTP \(httpResponse.statusCode).")
        }

        struct EmbedResponse: Codable {
            let embedding: [Double]
        }

        let decoded = try JSONDecoder().decode(EmbedResponse.self, from: data)
        guard !decoded.embedding.isEmpty else {
            throw OllamaError.generationFailed("Ollama returned an empty embedding.")
        }
        return decoded.embedding.map { Float($0) }
    }
}

enum OllamaError: LocalizedError {
    case connectionFailed
    case invalidURL
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed: "Could not connect to Ollama. Make sure it's running."
        case .invalidURL: "The Ollama base URL is invalid."
        case let .generationFailed(message): message
        }
    }
}
