import Foundation

enum RunbookCommandCopyService {
    static let safetyHeader = """
# Suggested commands only.
# reshelf has not executed or verified these commands.
# Review before running manually.
"""

    static func suggestedCommandsText(from markdown: String) -> String {
        let blocks = RunbookMarkdownParser.parse(markdown)
        var commands: [String] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            switch block {
            case .codeBlock(_, let code):
                appendCommandBlock(code, into: &commands)
            case .heading(_, let text):
                if isCommandSectionHeading(text) {
                    index += 1
                    while index < blocks.count {
                        switch blocks[index] {
                        case .codeBlock(_, let code):
                            appendCommandBlock(code, into: &commands)
                            index += 1
                        case .bulletList(let items):
                            for item in items where looksLikeCommandLine(item) {
                                commands.append(item.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            index += 1
                        default:
                            index = blocks.count
                        }
                    }
                    continue
                }
            default:
                break
            }
            index += 1
        }

        let unique = dedupe(commands)
        guard !unique.isEmpty else {
            return safetyHeader
        }
        return ([safetyHeader] + unique).joined(separator: "\n\n")
    }

    static func copyAllSuggestedCommands(from markdown: String) {
        RunbookExportService.copyToPasteboard(suggestedCommandsText(from: markdown))
    }

    private static func appendCommandBlock(_ code: String, into commands: inout [String]) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commands.append(trimmed)
    }

    private static func isCommandSectionHeading(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = ["command", "install", "run locally", "quick start", "setup", "build", "test"]
        return keywords.contains { lowered.contains($0) }
    }

    private static func looksLikeCommandLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["npm ", "pnpm ", "yarn ", "bun ", "cargo ", "go ", "swift ", "docker ", "pip ", "python ", "make ", "brew ", "curl "]
        return prefixes.contains { trimmed.hasPrefix($0) } || trimmed.hasPrefix("$ ")
    }

    private static func dedupe(_ commands: [String]) -> [String] {
        var seen: Set<String> = []
        return commands.filter { command in
            let key = command.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
