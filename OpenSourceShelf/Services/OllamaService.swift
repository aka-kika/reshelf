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
        // baseURL is user-edited in Settings — never force-unwrap it.
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.connectionFailed
        }
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
            guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
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
