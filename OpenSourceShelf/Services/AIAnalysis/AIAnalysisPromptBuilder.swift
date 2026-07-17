import Foundation

struct AIAnalysisEvidence: Equatable {
    var repository: RepositoryRecord
    var metadata: RepositoryMetadataRecord?
    var readmeExcerpt: String?
    var stackItems: [DetectedStackItemRecord]
    var manifests: [RepositoryManifestRecord]
}

enum AIAnalysisPromptBuilder {
    static func buildPrompt(evidence: AIAnalysisEvidence) -> String {
        """
        You are analyzing an open source repository for a local-first repo intelligence app.
        Use only the evidence below. Do not invent details.
        Return JSON only. No Markdown. No prose outside JSON.

        JSON schema:
        {
          "summary": "one short paragraph",
          "usefulness": "why this repo may matter in practical workflows",
          "classifications": ["short labels"],
          "risks": ["short risk labels or sentences"],
          "setupComplexity": 0,
          "localFirstScore": 0,
          "experimentationPriority": 0,
          "personalRelevance": 0,
          "relationshipHints": ["lightweight relationship hints"]
        }

        Scoring rules:
        - Scores are integers from 0 to 10.
        - setupComplexity: 0 is trivial, 10 is difficult.
        - localFirstScore: higher means more local/self-hosted/offline-friendly.
        - experimentationPriority: higher means worth trying soon.
        - personalRelevance: higher means useful for local AI, macOS tooling, agent workflows, developer productivity, or private local-first work.
        - Base scores only on evidence.

        Evidence:
        \(evidenceBlock(evidence))
        """
    }

    /// Prompt for guided generation (Apple FoundationModels): the output schema is
    /// enforced by @Generable, so only scoring rules and evidence are needed.
    static func buildGuidedPrompt(evidence: AIAnalysisEvidence) -> String {
        """
        Analyze this open source repository using only the evidence below.

        Scoring rules:
        - Scores are integers from 0 to 10.
        - setupComplexity: 0 is trivial, 10 is difficult.
        - localFirstScore: higher means more local/self-hosted/offline-friendly.
        - experimentationPriority: higher means worth trying soon.
        - personalRelevance: higher means useful for local AI, macOS tooling, agent workflows, developer productivity, or private local-first work.

        Evidence:
        \(evidenceBlock(evidence))
        """
    }

    private static func evidenceBlock(_ evidence: AIAnalysisEvidence) -> String {
        let repository = evidence.repository
        let metadata = evidence.metadata
        let stack = evidence.stackItems
            .prefix(40)
            .map { "- \($0.category): \($0.name) via \($0.detectionSource) at \($0.evidencePath ?? "unknown")" }
            .joined(separator: "\n")
        let manifests = evidence.manifests
            .prefix(30)
            .map { "- \($0.type) (\($0.ecosystem)): \($0.path)" }
            .joined(separator: "\n")

        return """
        Repository:
        - name: \(repository.fullName)
        - url: \(repository.githubURL)
        - description: \(metadata?.description ?? "No description")
        - stars: \(metadata?.stars.map(String.init) ?? "unknown")
        - forks: \(metadata?.forks.map(String.init) ?? "unknown")
        - license: \(metadata?.licenseSPDX ?? "unknown")
        - primary language: \(metadata?.primaryLanguage ?? "unknown")
        - latest commit sha: \(repository.latestCommitSHA ?? "unknown")

        Detected stack:
        \(stack.isEmpty ? "- none detected" : stack)

        Manifests:
        \(manifests.isEmpty ? "- none detected" : manifests)

        README excerpt:
        \(sanitize(evidence.readmeExcerpt ?? "No README excerpt available."))
        """
    }

    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefixString(4_000)
    }
}

private extension String {
    func prefixString(_ maxLength: Int) -> String {
        String(prefix(maxLength))
    }
}
