import SwiftUI

struct CompareInspectorView: View {
    let result: RepositoryComparisonResult?
    let selectedRanking: ComparisonRankingEntry?
    var onCopySummary: (() -> Void)?
    var onExportMarkdown: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                HStack {
                    Text("Compare Inspector")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if result != nil {
                        Button("Copy Summary", action: { onCopySummary?() })
                            .controlSize(.small)
                    }
                }
            }

            if let result, let ranking = displayedRanking(in: result),
               let profile = result.profiles.first(where: { $0.repositoryID == ranking.repositoryID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if ranking.rank == 1 {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.yellow)
                                }
                                Text(profile.fullName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Text("Rank #\(ranking.rank) · score \(Int(ranking.compositeScore.rounded()))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        metricsGrid(profile)

                        if let summary = profile.summary ?? profile.description, !summary.isEmpty {
                            inspectorSection("Summary") {
                                Text(summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        inspectorSection("Why it ranked here") {
                            Text(ranking.explanation)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !ranking.strongestSignals.isEmpty {
                            inspectorSection("Strongest signals") {
                                chipList(ranking.strongestSignals)
                            }
                        }

                        if !ranking.weakestSignals.isEmpty {
                            inspectorSection("Weakest signals") {
                                chipList(ranking.weakestSignals)
                            }
                        }

                        if !profile.stackItems.isEmpty {
                            inspectorSection("Stack") {
                                chipList(Array(profile.stackItems.prefix(16)))
                            }
                        }

                        if !profile.ecosystemNames.isEmpty {
                            inspectorSection("Ecosystems") {
                                chipList(profile.ecosystemNames)
                            }
                        }

                        if !profile.risks.isEmpty {
                            inspectorSection("Risks") {
                                ForEach(profile.risks, id: \.self) { risk in
                                    Text("· \(risk)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                CompareEmptyState(
                    title: "No comparison yet",
                    message: "Run a comparison, then click a ranked repo to inspect it here.",
                    systemImage: "sidebar.right"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func chipList(_ items: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
        }
    }

    /// The repo to focus on: the one the user clicked in the ranking, else the winner.
    private func displayedRanking(in result: RepositoryComparisonResult) -> ComparisonRankingEntry? {
        selectedRanking ?? result.rankings.first
    }

    /// Compact two-column grid of the focused repo's key metrics.
    private func metricsGrid(_ profile: RepositoryComparisonProfile) -> some View {
        let metrics: [(String, String)] = [
            ("Stars", profile.stars.map(formatCount) ?? "—"),
            ("Language", profile.primaryLanguage ?? "—"),
            ("Local-first", profile.localFirstScore.map { "\($0)/10" } ?? "—"),
            ("Setup", profile.setupComplexity.map { "\($0)/10" } ?? "—"),
            ("Graph centrality", "\(profile.graphCentrality)"),
            ("Signals", "\(profile.recommendationCount)")
        ]
        return LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading),
                      GridItem(.flexible(), alignment: .leading)],
            spacing: 12
        ) {
            ForEach(metrics, id: \.0) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.0)
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                    Text(metric.1)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        return "\(count)"
    }
}

struct CompareEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.35))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
