// afm-analyze — validation harness for reshelf's Apple Intelligence repo analysis.
// Runs the same guided-generation schema the app uses, against a real cloned repo,
// so output quality and latency can be checked without launching the app.
//
// Usage:  afm-analyze /path/to/cloned/repo
// Output: the analysis payload as JSON on stdout, timing on stderr.
// Exit codes: 0 ok, 2 model unavailable, 1 anything else.
//
// Build: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
//        swiftc -O -parse-as-library afm_analyze.swift -o afm-analyze

import Foundation
import FoundationModels

@Generable
struct RepositoryAnalysisGeneration {
    @Guide(description: "One short paragraph: what the repository is and does")
    var summary: String
    @Guide(description: "Why this repo may matter in practical workflows")
    var usefulness: String
    @Guide(description: "Short classification labels, e.g. 'CLI tool', 'macOS app', 'AI agent framework'")
    var classifications: [String]
    @Guide(description: "Short risk labels or sentences covering license, maintenance, or security concerns")
    var risks: [String]
    @Guide(description: "Setup difficulty: 0 is trivial, 10 is difficult")
    var setupComplexity: Int
    @Guide(description: "0 to 10, higher means more local, self-hosted, or offline-friendly")
    var localFirstScore: Int
    @Guide(description: "0 to 10, higher means worth experimenting with soon")
    var experimentationPriority: Int
    @Guide(description: "0 to 10 relevance to local AI, macOS tooling, agent workflows, or developer productivity")
    var personalRelevance: Int
    @Guide(description: "Lightweight hints about related tools or ecosystems")
    var relationshipHints: [String]
}

func readmeExcerpt(repoPath: String) -> String {
    let candidates = ["README.md", "Readme.md", "readme.md", "README", "README.markdown", "README.rst"]
    for candidate in candidates {
        let url = URL(fileURLWithPath: repoPath).appendingPathComponent(candidate)
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return String(text.prefix(4_000))
        }
    }
    return "No README excerpt available."
}

@main
struct Main {
    static func main() async {
        guard CommandLine.arguments.count > 1 else {
            FileHandle.standardError.write(Data("usage: afm-analyze /path/to/repo\n".utf8))
            exit(1)
        }
        let repoPath = CommandLine.arguments[1]
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            FileHandle.standardError.write(Data("model unavailable: \(model.availability)\n".utf8))
            exit(2)
        }

        let prompt = """
        Analyze this open source repository using only the evidence below.

        Scoring rules:
        - Scores are integers from 0 to 10.
        - setupComplexity: 0 is trivial, 10 is difficult.
        - localFirstScore: higher means more local/self-hosted/offline-friendly.
        - experimentationPriority: higher means worth trying soon.
        - personalRelevance: higher means useful for local AI, macOS tooling, agent workflows, developer productivity, or private local-first work.

        Evidence:
        Repository:
        - name: \(repoName)

        README excerpt:
        \(readmeExcerpt(repoPath: repoPath))
        """

        let session = LanguageModelSession(instructions: """
            You analyze open source repositories for a local-first repo intelligence app. \
            Use only the provided evidence. Do not invent details. \
            Scores are integers from 0 to 10; base them only on evidence.
            """)

        do {
            let start = Date()
            let result = try await session.respond(to: prompt, generating: RepositoryAnalysisGeneration.self).content
            let elapsed = Date().timeIntervalSince(start)

            let out: [String: Any] = [
                "summary": result.summary,
                "usefulness": result.usefulness,
                "classifications": result.classifications,
                "risks": result.risks,
                "setupComplexity": result.setupComplexity,
                "localFirstScore": result.localFirstScore,
                "experimentationPriority": result.experimentationPriority,
                "personalRelevance": result.personalRelevance,
                "relationshipHints": result.relationshipHints,
            ]
            let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
            FileHandle.standardError.write(Data(String(format: "elapsed: %.1fs\n", elapsed).utf8))
        } catch {
            FileHandle.standardError.write(Data("analysis failed: \(error)\n".utf8))
            exit(1)
        }
    }
}
