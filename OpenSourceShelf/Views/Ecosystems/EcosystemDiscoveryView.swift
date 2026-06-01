import SwiftUI

struct EcosystemDiscoveryView: View {
    let title: String
    let subtitle: String
    let clusterTypes: [String]
    @Binding var selectedCluster: EcosystemClusterSummary?
    var onOpenRepository: (String) -> Void

    @State private var clusters: [EcosystemClusterSummary] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(action: refresh) {
                        if isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh \(title.lowercased())")
                    .disabled(isRefreshing)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(16)
            }

            if clusters.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(clusters) { cluster in
                            EcosystemClusterCard(
                                cluster: cluster,
                                isSelected: selectedCluster?.id == cluster.id,
                                onSelect: { selectedCluster = cluster },
                                onOpenRepository: onOpenRepository
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            reload()
        }
        .onChange(of: clusters) { _, updated in
            if let selected = selectedCluster,
               !updated.contains(where: { $0.id == selected.id }) {
                selectedCluster = nil
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.bottom, 4)

            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No discovery clusters yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Fetch intelligence for repos in your catalog, wait for recommendations to finish, then generate clusters here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Generate Ecosystems", action: refresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRefreshing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func reload() {
        do {
            try IntelligenceDatabase.shared.initialize()
            clusters = try IntelligenceDatabase.shared.fetchEcosystemClusters(types: clusterTypes)
            errorMessage = nil
        } catch {
            clusters = []
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        isRefreshing = true
        Task {
            do {
                _ = try await EcosystemDiscoveryService.refresh()
                await MainActor.run {
                    reload()
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRefreshing = false
                }
            }
        }
    }
}

private struct EcosystemClusterCard: View {
    let cluster: EcosystemClusterSummary
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenRepository: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(cluster.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(cluster.score.rounded()))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(scoreColor)
                    Text("\(Int((cluster.confidence * 100).rounded()))%")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            repositoryChipGroup
            chipGroup(title: "Common stack", values: EcosystemClusterJSON.decode(cluster.commonStackJSON), limit: 8, color: .purple)
            chipGroup(title: "Integrations", values: EcosystemClusterJSON.decode(cluster.integrationsJSON), limit: 6, color: .green)

            let highlights = EcosystemClusterJSON.decode(cluster.recommendationHighlightsJSON)
            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Recommendation highlights")
                    ForEach(highlights.prefix(3), id: \.self) { highlight in
                        Text(highlight)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            let missingPieces = EcosystemClusterJSON.decode(cluster.missingPiecesJSON)
            if !missingPieces.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Missing pieces")
                    ForEach(missingPieces, id: \.self) { missing in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .padding(.top, 1)
                            Text(missing)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
    }

    private var repositoryChipGroup: some View {
        Group {
            let links = EcosystemClusterJSON.repositoryLinks(from: cluster)
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel("Repositories")
                    FlowLayout(spacing: 5) {
                        ForEach(links.prefix(5), id: \.id) { link in
                            Button(link.name) {
                                onOpenRepository(link.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.blue.opacity(0.08))
                            )
                            .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    private var scoreColor: Color {
        if cluster.score >= 70 {
            return .green
        }
        if cluster.score >= 45 {
            return .orange
        }
        return .secondary
    }

    private func chipGroup(title: String, values: [String], limit: Int, color: Color) -> some View {
        Group {
            if !values.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel(title)
                    FlowLayout(spacing: 5) {
                        ForEach(values.prefix(limit), id: \.self) { value in
                            Text(value)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(color.opacity(0.08))
                                )
                                .foregroundStyle(color)
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

enum EcosystemClusterJSON {
    struct RepositoryLink: Identifiable {
        let id: String
        let name: String
    }

    static func decode(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    static func repositoryLinks(from cluster: EcosystemClusterSummary) -> [RepositoryLink] {
        let ids = decode(cluster.repositoryIDsJSON)
        let names = decode(cluster.repositoryNamesJSON)
        let count = min(ids.count, names.count)
        return (0..<count).map { index in
            RepositoryLink(id: ids[index], name: names[index])
        }
    }
}

struct DiscoveryClusterInspectorView: View {
    let cluster: EcosystemClusterSummary?
    var onOpenRepository: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                Text("Inspector")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(cluster == nil ? .secondary : .primary)
            }

            if let cluster {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cluster.name)
                                .font(.system(size: 15, weight: .semibold))
                            Text(cluster.explanation)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 16) {
                            metricBlock(title: "Score", value: "\(Int(cluster.score.rounded()))")
                            metricBlock(title: "Confidence", value: "\(Int((cluster.confidence * 100).rounded()))%")
                        }

                        inspectorRepositorySection(cluster)
                        inspectorStringSection(title: "Common stack", values: EcosystemClusterJSON.decode(cluster.commonStackJSON))
                        inspectorStringSection(title: "Strongest tools", values: EcosystemClusterJSON.decode(cluster.strongestToolsJSON))
                        inspectorStringSection(title: "Integrations", values: EcosystemClusterJSON.decode(cluster.integrationsJSON))
                        inspectorStringSection(title: "Highlights", values: EcosystemClusterJSON.decode(cluster.recommendationHighlightsJSON))
                        inspectorStringSection(title: "Missing pieces", values: EcosystemClusterJSON.decode(cluster.missingPiecesJSON))
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "Select a cluster",
                    systemImage: "sidebar.right",
                    description: Text("Choose a cluster in the list to inspect repos, shared stack, and gaps.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
        }
    }

    @ViewBuilder
    private func inspectorRepositorySection(_ cluster: EcosystemClusterSummary) -> some View {
        let links = EcosystemClusterJSON.repositoryLinks(from: cluster)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Repositories")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(links) { link in
                    Button {
                        onOpenRepository(link.id)
                    } label: {
                        HStack {
                            Text(link.name)
                                .font(.system(size: 12))
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func inspectorStringSection(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
