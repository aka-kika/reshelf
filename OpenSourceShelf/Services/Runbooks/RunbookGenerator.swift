import Foundation

enum RunbookGenerator {
    static let disclaimer = """
    > These commands were generated from repository evidence and have **not been executed** by reshelf. Review before running.
    """

    static let commandDisclaimer = "Suggested only. reshelf has not executed this command."

    static func buildDeterministicMarkdown(from evidence: RunbookEvidence) -> String {
        let repo = evidence.repository
        let title = "Local Test Runbook — \(repo.fullName)"
        var lines: [String] = []

        lines.append("# Local Test Runbook")
        lines.append("")
        lines.append(disclaimer)
        lines.append("")

        lines.append("## Repository")
        lines.append("")
        lines.append("- **Name:** \(repo.fullName)")
        lines.append("- **GitHub:** \(repo.githubURL)")
        if let license = evidence.metadata?.licenseSPDX, !license.isEmpty {
            lines.append("- **License:** \(license)")
        }
        if let language = evidence.metadata?.primaryLanguage, !language.isEmpty {
            lines.append("- **Primary language:** \(language)")
        }
        lines.append("")

        lines.append("## What This Repo Is")
        lines.append("")
        if let summary = evidence.aiInsight?.summary, !summary.isEmpty {
            lines.append("*AI-refined wording* · Static analysis evidence")
            lines.append("")
            lines.append(summary)
        } else if let description = evidence.metadata?.description, !description.isEmpty {
            lines.append("*Repository metadata evidence*")
            lines.append("")
            lines.append(description)
        } else {
            lines.append("Unknown — no README summary or metadata description was available.")
        }
        lines.append("")

        lines.append("## Best Guess Setup Path")
        lines.append("")
        lines.append("*Inferred caution* · Based on manifests and stack detections")
        lines.append("")
        lines.append(setupPathSummary(for: evidence))
        lines.append("")

        lines.append("## Prerequisites")
        lines.append("")
        appendListOrUnknown(prerequisites(for: evidence), into: &lines)
        lines.append("")

        lines.append("## Clone Location")
        lines.append("")
        if let path = evidence.clonePath, !path.isEmpty {
            lines.append("```text")
            lines.append(path)
            lines.append("```")
        } else {
            lines.append("Unknown — repository has not been cloned locally yet.")
        }
        lines.append("")

        appendCommandSection("Install Commands", commands: evidence.commands.installCommands, into: &lines)
        appendCommandSection("Run Commands", commands: evidence.commands.runCommands, into: &lines)

        lines.append("## Environment Variables")
        lines.append("")
        if evidence.envFileExamples.isEmpty && evidence.commands.environmentNotes.isEmpty {
            lines.append("Unknown — no `.env.example` or similar file was found.")
        } else {
            for example in evidence.envFileExamples {
                lines.append("```env")
                lines.append(example)
                lines.append("```")
                lines.append("")
            }
            for note in evidence.commands.environmentNotes {
                lines.append("```env")
                lines.append(note)
                lines.append("```")
                lines.append("")
            }
        }

        appendCommandSection("Docker Option", commands: evidence.commands.dockerCommands, into: &lines)

        lines.append("## Local AI / Ollama Notes")
        lines.append("")
        let aiItems = evidence.stackItems.filter { $0.category == "ai_integration" }.map(\.name)
        if aiItems.isEmpty {
            lines.append("No explicit local AI integration detected in static analysis.")
        } else {
            appendListOrUnknown(aiItems, into: &lines)
        }
        if let usefulness = evidence.aiInsight?.usefulness, !usefulness.isEmpty {
            lines.append("")
            lines.append(usefulness)
        }
        lines.append("")

        lines.append("## Database Notes")
        lines.append("")
        let databases = evidence.stackItems.filter { $0.category == "database" }.map(\.name)
        if databases.isEmpty {
            lines.append("Unknown — no database stack items detected.")
        } else {
            appendListOrUnknown(databases, into: &lines)
        }
        lines.append("")

        lines.append("## Risk Notes")
        lines.append("")
        let risks = decodeStringArray(evidence.aiInsight?.risksJSON ?? "[]")
        if risks.isEmpty {
            lines.append("No AI risk notes available.")
        } else {
            appendListOrUnknown(risks, into: &lines)
        }
        if let score = evidence.repositoryScore {
            lines.append("")
            lines.append("- Setup complexity score: \(score.setupComplexity)/10")
        }
        lines.append("")

        lines.append("## Verification Checklist")
        lines.append("")
        lines.append("- [ ] Clone exists at the path above (or clone manually)")
        lines.append("- [ ] Install prerequisites")
        lines.append("- [ ] Run suggested install commands in a clean shell")
        lines.append("- [ ] Run the primary dev/start command")
        lines.append("- [ ] Confirm the app/service responds locally")
        lines.append("- [ ] Review environment variables before exposing ports")
        lines.append("")

        lines.append("## What Is Unverified")
        lines.append("")
        var unverified: [String] = []
        if evidence.readmeExcerpt == nil { unverified.append("README content") }
        if evidence.manifests.isEmpty { unverified.append("Package manifests") }
        if evidence.clonePath == nil { unverified.append("Local clone path") }
        if evidence.commands.installCommands.isEmpty { unverified.append("Install commands") }
        if evidence.commands.runCommands.isEmpty { unverified.append("Run commands") }
        if unverified.isEmpty {
            lines.append("All major sections had some evidence, but commands remain **suggested only** until you verify them.")
        } else {
            appendListOrUnknown(unverified.map { "Missing evidence for \($0)" }, into: &lines)
        }
        lines.append("")
        lines.append("---")
        lines.append("*Generated by reshelf (deterministic)*")

        return lines.joined(separator: "\n")
    }

    static func buildAIPrompt(from evidence: RunbookEvidence, deterministicDraft: String) -> String {
        let stackNames = evidence.stackItems.map { "\($0.category): \($0.name)" }.joined(separator: ", ")
        let manifestPaths = evidence.manifests.map(\.path).joined(separator: ", ")
        let risks = decodeStringArray(evidence.aiInsight?.risksJSON ?? "[]").joined(separator: "; ")

        return """
        You are helping a developer test an open-source repository locally.
        Use ONLY the evidence below. Do NOT invent commands, ports, or features.
        If evidence is missing, write "Unknown" for that subsection.
        Output markdown only with these sections:
        # Local Test Runbook
        ## Repository
        ## What This Repo Is
        ## Best Guess Setup Path
        ## Prerequisites
        ## Clone Location
        ## Install Commands
        ## Run Commands
        ## Environment Variables
        ## Docker Option
        ## Local AI / Ollama Notes
        ## Database Notes
        ## Risk Notes
        ## Verification Checklist
        ## What Is Unverified

        Rules:
        - Prefix the document with this disclaimer exactly:
        \(disclaimer)
        - Label every command block as suggested, not executed.
        - Include this line under command sections: \(commandDisclaimer)
        - Tag evidence sources when possible: README evidence, Manifest evidence, Static analysis evidence, AI-refined wording, Inferred caution.
        - Prefer README and manifest evidence over guessing.
        - Keep commands copy-pasteable when evidence supports them.
        - Be conservative.

        Repository: \(evidence.repository.fullName)
        GitHub: \(evidence.repository.githubURL)
        Clone path: \(evidence.clonePath ?? "Unknown")
        Description: \(evidence.metadata?.description ?? "Unknown")
        AI summary: \(evidence.aiInsight?.summary ?? "Unknown")
        Risks: \(risks.isEmpty ? "Unknown" : risks)
        Manifests: \(manifestPaths.isEmpty ? "None" : manifestPaths)
        Stack: \(stackNames.isEmpty ? "None" : stackNames)
        README excerpt:
        \(evidence.readmeExcerpt ?? "Unknown")

        Deterministic draft to refine (do not contradict strong manifest evidence):
        \(deterministicDraft.prefix(6_000))
        """
    }

    private static func setupPathSummary(for evidence: RunbookEvidence) -> String {
        if !evidence.commands.dockerCommands.isEmpty {
            return "Docker/Compose appears supported. Native install may also be possible depending on manifests."
        }
        if evidence.manifests.contains(where: { $0.type == "package_json" }) {
            return "Node/JavaScript project — install dependencies with the detected package manager, then run a dev/start script."
        }
        if evidence.manifests.contains(where: { $0.type == "cargo_toml" }) {
            return "Rust project — use Cargo build/run from the clone directory."
        }
        if evidence.manifests.contains(where: { $0.type == "swift_package" }) {
            return "Swift package — use `swift build` / `swift run` from the clone directory."
        }
        if evidence.manifests.contains(where: { $0.type == "go_module" }) {
            return "Go module — download modules and run from repository root."
        }
        if evidence.manifests.contains(where: { $0.type == "requirements" || $0.type == "pyproject" }) {
            return "Python project — create a virtual environment, install dependencies, then run the entrypoint from README if present."
        }
        return "Unknown — inspect README and manifests manually."
    }

    private static func prerequisites(for evidence: RunbookEvidence) -> [String] {
        var items: [String] = []
        let manifestTypes = Set(evidence.manifests.map(\.type))
        if manifestTypes.contains("package_json") { items.append("Node.js + npm/pnpm/yarn/bun (match lockfile if present)") }
        if manifestTypes.contains("cargo_toml") { items.append("Rust toolchain (rustup, cargo)") }
        if manifestTypes.contains("go_module") { items.append("Go toolchain") }
        if manifestTypes.contains("swift_package") { items.append("Swift toolchain (Xcode or swift CLI)") }
        if manifestTypes.contains("requirements") || manifestTypes.contains("pyproject") { items.append("Python 3.x") }
        if manifestTypes.contains("dockerfile") || manifestTypes.contains("docker_compose") { items.append("Docker (optional)") }
        for runtime in evidence.stackItems.filter({ $0.category == "runtime" }) {
            items.append(runtime.name)
        }
        return Array(Set(items)).sorted()
    }

    private static func appendCommandSection(_ title: String,
                                             commands: [RunbookCommand],
                                             into lines: inout [String]) {
        lines.append("## \(title)")
        lines.append("")
        if commands.isEmpty {
            lines.append("Unknown — no evidence-backed commands found.")
        } else {
            lines.append("*User-visible command suggestion* · \(commandDisclaimer)")
            lines.append("")
            for command in commands {
                lines.append("- *\(evidenceLabel(for: command.source))* · \(command.confidence) confidence · source: \(command.source)")
                lines.append("```bash")
                lines.append(command.command)
                lines.append("```")
                lines.append("")
            }
        }
        lines.append("")
    }

    private static func evidenceLabel(for source: String) -> String {
        let lowered = source.lowercased()
        if lowered.contains("readme") { return "README evidence" }
        if lowered.contains("package.json") || lowered.contains("manifest") || lowered.contains("cargo")
            || lowered.contains("go.mod") || lowered.contains("requirements") || lowered.contains("docker") {
            return "Manifest evidence"
        }
        if lowered.contains("makefile") { return "Manifest evidence" }
        return "Static analysis evidence"
    }

    private static func appendListOrUnknown(_ items: [String], into lines: inout [String]) {
        if items.isEmpty {
            lines.append("Unknown")
        } else {
            for item in items {
                lines.append("- \(item)")
            }
        }
    }

    private static func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}
