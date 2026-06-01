import AppKit
import Foundation
import UniformTypeIdentifiers

enum ComparisonExportService {
    static func markdown(for result: RepositoryComparisonResult) -> String {
        let title = result.profiles.map(\.fullName).joined(separator: " vs ")
        let date = formattedDate(result.generatedAt)
        var lines: [String] = []

        lines.append("# Repository Comparison")
        lines.append("")
        lines.append("**Compared:** \(title)")
        lines.append("**Generated:** \(date)")
        lines.append("")

        lines.append("## Decision summary")
        lines.append("")
        for line in result.decisionSummary {
            lines.append("- **\(line.category):** \(line.winnerLabel) — \(line.explanation)")
        }
        lines.append("")

        lines.append("## Scores & ranking")
        lines.append("")
        for ranking in result.rankings {
            lines.append("\(ranking.rank). **\(ranking.fullName)** — score \(Int(ranking.compositeScore.rounded()))")
            lines.append("   - \(ranking.explanation)")
            if !ranking.strongestSignals.isEmpty {
                lines.append("   - Strong: \(ranking.strongestSignals.joined(separator: ", "))")
            }
            if !ranking.weakestSignals.isEmpty {
                lines.append("   - Weak: \(ranking.weakestSignals.joined(separator: ", "))")
            }
        }
        lines.append("")

        lines.append("## Stack comparison")
        lines.append("")
        if !result.sharedStack.isEmpty {
            lines.append("**Shared:** \(result.sharedStack.joined(separator: ", "))")
            lines.append("")
        }
        for profile in result.profiles {
            if let unique = result.uniqueStack[profile.repositoryID], !unique.isEmpty {
                lines.append("**Unique to \(profile.fullName):** \(unique.joined(separator: ", "))")
            }
        }
        lines.append("")

        lines.append("## Risks")
        lines.append("")
        for profile in result.profiles where !profile.risks.isEmpty {
            lines.append("### \(profile.fullName)")
            for risk in profile.risks {
                lines.append("- \(risk)")
            }
            lines.append("")
        }

        lines.append("## Graph overlap")
        lines.append("")
        if !result.graphOverlap.sharedNeighbors.isEmpty {
            lines.append("**Shared neighbors:** \(result.graphOverlap.sharedNeighbors.joined(separator: ", "))")
        }
        for path in result.graphOverlap.pairPaths {
            lines.append("- \(path.fromLabel) ↔ \(path.toLabel) (\(path.hopCount) hops): \(path.explanation)")
        }
        if !result.graphOverlap.alternativeLinks.isEmpty {
            lines.append("**Alternative links:** \(result.graphOverlap.alternativeLinks.joined(separator: ", "))")
        }
        lines.append("")

        lines.append("## Recommendation signals")
        lines.append("")
        for profile in result.profiles {
            lines.append("- **\(profile.fullName):** \(profile.recommendationCount) recommendation signal(s)")
        }
        lines.append("")

        lines.append("## Comparison matrix")
        lines.append("")
        let headers = result.profiles.map(\.fullName)
        lines.append("| Signal | \(headers.joined(separator: " | ")) |")
        lines.append("| --- | \(headers.map { _ in "---" }.joined(separator: " | ")) |")
        for row in result.matrixRows {
            let values = result.profiles.map { row.values[$0.repositoryID] ?? "—" }
            lines.append("| \(row.label) | \(values.joined(separator: " | ")) |")
        }
        lines.append("")

        lines.append("---")
        lines.append("*Exported from reshelf*")
        return lines.joined(separator: "\n")
    }

    static func copySummary(for result: RepositoryComparisonResult) -> String {
        var lines: [String] = []
        let names = result.profiles.map(\.fullName).joined(separator: " vs ")

        lines.append("Comparison: \(names)")
        lines.append("")

        if let overall = result.decisionSummary.first(where: { $0.category == "Overall recommendation" })
            ?? result.rankings.first.map({
                ComparisonDecisionLine(category: "Overall recommendation",
                                       winnerRepositoryID: $0.repositoryID,
                                       winnerLabel: $0.fullName,
                                       explanation: $0.explanation)
            }) {
            lines.append("Best overall: \(overall.winnerLabel)")
            lines.append(overall.explanation)
            lines.append("")
        }

        let useCases = result.decisionSummary.filter { $0.category != "Overall recommendation" }
        if !useCases.isEmpty {
            lines.append("Best for specific use cases:")
            for line in useCases.prefix(4) {
                lines.append("- \(line.category): \(line.winnerLabel) — \(line.explanation)")
            }
            lines.append("")
        }

        if result.rankings.count >= 2 {
            let bottom = result.rankings.last!
            lines.append("Key tradeoffs:")
            if !bottom.weakestSignals.isEmpty {
                lines.append("- \(bottom.fullName) is weaker on: \(bottom.weakestSignals.joined(separator: ", "))")
            }
            if let top = result.rankings.first, !top.strongestSignals.isEmpty {
                lines.append("- \(top.fullName) leads on: \(top.strongestSignals.joined(separator: ", "))")
            }
            lines.append("")
        }

        if let recommendation = result.decisionSummary.first(where: { $0.category == "Overall recommendation" }) {
            lines.append("Recommendation: Choose \(recommendation.winnerLabel) unless you specifically need a different stack fit.")
        } else if let top = result.rankings.first {
            lines.append("Recommendation: Start with \(top.fullName) for the strongest combined signals in this comparison.")
        }

        return lines.joined(separator: "\n")
    }

    static func defaultFilename(for result: RepositoryComparisonResult) -> String {
        let slug = result.profiles.map { slugComponent(from: $0.fullName) }
        let date = exportDateStamp(from: result.generatedAt)
        if slug.count == 2 {
            return "comparison-\(slug[0])-vs-\(slug[1])-\(date).md"
        }
        let compact = slug.prefix(3).joined(separator: "-")
        return "comparison-\(compact)-\(date).md"
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func saveMarkdown(_ text: String, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.title = "Export Comparison"
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func slugComponent(from fullName: String) -> String {
        let base = fullName.split(separator: "/").last.map(String.init) ?? fullName
        let lowered = base.lowercased()
        let allowed = lowered.map { char -> Character in
            char.isLetter || char.isNumber ? char : "-"
        }
        return String(allowed)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func exportDateStamp(from iso: String) -> String {
        if iso.count >= 10 {
            return String(iso.prefix(10))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso
    }
}
