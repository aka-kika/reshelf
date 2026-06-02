import SwiftUI
import SwiftData

struct InspectView: View {
    let project: ToolProject
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @AppStorage(LabsFeatures.storageKey) private var labsFeaturesEnabled = false
    @Query private var appSettingsQuery: [AppSettings]
    @State private var isEditing: Bool = false
    @State private var cloneSnapshot: CloneStatusSnapshot?
    @State private var stackItems: [DetectedStackItemRecord] = []
    @State private var aiInsight: AIInsightRecord?
    @State private var repositoryScore: RepositoryScoreRecord?
    @State private var relationships: [GraphRelationshipSummary] = []
    @State private var recommendations: [RepositoryRecommendationSummary] = []
    @State private var intelligenceRepositoryID: String?
    @State private var cloneStatusError: String?
    @State private var catalogSnapshot: CatalogIntelligenceStatusSnapshot = .notFetched
    @State private var isFetchingIntelligence = false
    @State private var intelligenceActionNotice: String?
    @State private var githubMetadata: RepositoryMetadataRecord?
    @State private var isCloningLocally = false
    @State private var cloneActionNotice: String?
    @State private var showsAllRelationships = false
    @State private var showsFullStack = false
    @State private var showsAllRecommendations = false
    @State private var showsIntelligenceDetails = false
    @State private var isCloningLocalCopy = false
    @State private var localCopyNotice: String?

    private var inspectorSettings: AppSettings {
        appSettingsQuery.first ?? AppSettings()
    }

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                HStack(spacing: 10) {
                    ProjectIcon(project: project, size: 28)

                    Text(project.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    StatusBadge(status: project.status)

                    if labsFeaturesEnabled {
                        IntelligenceStatusChip(snapshot: catalogSnapshot)
                    }

                    Spacer(minLength: 0)
                }
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    metadataSection

                    if !project.longDescription.isEmpty {
                        Divider().padding(.vertical, 16)
                        sectionTitle("Description")
                        Text(project.longDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }

                    // Render configurable inspector sections in user-defined order.
                    // Intelligence-derived sections (stack / relationships /
                    // recommendations) are a v2 surface — only under Labs.
                    ForEach(inspectorSettings.inspectorSectionOrder) { section in
                        if labsFeaturesEnabled || !section.isIntelligence {
                            inspectorSectionContent(section)
                        }
                    }

                    // Local copy — clone the repo to disk (v1; AI-free). With Labs
                    // on, the richer intelligence clone/fetch section below replaces it.
                    if !labsFeaturesEnabled {
                        Divider().padding(.vertical, 12)
                        localCopySection
                    }

                    // Deep intelligence + clone (v2 — Labs only)
                    if labsFeaturesEnabled {
                        // Deep intelligence fixed sections (not reorderable)
                        if showsDeepIntelligence {
                            Divider().padding(.vertical, 12)
                            intelligenceSection

                            Divider().padding(.vertical, 12)
                            compareActionsSection

                            Divider().padding(.vertical, 12)
                            RunbookSectionView(repositoryID: intelligenceRepositoryID,
                                               clonePath: cloneSnapshot?.cloneState.path,
                                               isIntelligenceReady: isIntelligenceReady)
                        }

                        Divider().padding(.vertical, 12)
                        intelligenceFetchSection

                        Divider().padding(.vertical, 12)
                        cloneStatusSection
                    }

                    Divider().padding(.vertical, 12)
                    HStack {
                        Text("Added")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(project.addedDate, format: .dateTime.day().month().year())
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(action: { isEditing = true }) {
                            Label("Edit", systemImage: "pencil")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)

                        Button(role: .destructive, action: deleteProject) {
                            Label("Delete", systemImage: "trash")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isEditing) {
            EditProjectSheet(project: project, isPresented: $isEditing)
        }
        .task(id: project.id) {
            await loadCloneStatus()
        }
        .onChange(of: appRefreshStore.catalogRevision) { _, _ in
            Task { await loadCloneStatus() }
        }
        .onChange(of: appRefreshStore.intelligenceRevision(for: intelligenceRepositoryID)) { _, _ in
            Task { await loadCloneStatus() }
        }
        .onChange(of: appRefreshStore.runbookRevision(for: intelligenceRepositoryID)) { _, _ in
            Task { await loadCloneStatus() }
        }
    }

    private var isIntelligenceReady: Bool {
        catalogSnapshot.status == .ready
    }

    private var showsDeepIntelligence: Bool {
        cloneSnapshot?.cloneState.status == "cloned"
            || !stackItems.isEmpty
            || aiInsight != nil
            || !relationships.isEmpty
            || !recommendations.isEmpty
    }

    /// Renders a single inspector section by its enum case, respecting visibility and data availability.
    @ViewBuilder
    private func inspectorSectionContent(_ section: InspectorSection) -> some View {
        switch section {
        case .useCases:
            if !project.useCases.isEmpty, inspectorSettings.showInspectorUseCases {
                Divider().padding(.vertical, 16)
                sectionTitle("Use Cases")
                Text("Practical ways this tool fits into real workflows:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.bottom, 8)
                ForEach(project.useCases, id: \.self) { useCase in
                    useCaseRow(useCase)
                }
            }

        case .tags:
            if !project.tags.isEmpty, inspectorSettings.showInspectorTags {
                Divider().padding(.vertical, 16)
                sectionTitle("Tags")
                FlowLayout(spacing: 6) {
                    ForEach(project.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
            }

        case .notes:
            if !project.notes.isEmpty, inspectorSettings.showInspectorNotes {
                Divider().padding(.vertical, 16)
                sectionTitle("Notes")
                Text(project.notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

        case .personalFit:
            if inspectorSettings.showInspectorPersonalFit {
                Divider().padding(.vertical, 16)
                sectionTitle("Personal Fit")
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= project.fitScore ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .foregroundStyle(i <= project.fitScore ? .yellow : .secondary.opacity(0.3))
                    }
                    Text(fitLabel(for: project.fitScore))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
            }

        case .github:
            if shouldShowGitHubMetadataSection, inspectorSettings.showInspectorGitHub {
                Divider().padding(.vertical, 12)
                githubMetadataSection
            }

        case .stack:
            if showsDeepIntelligence, inspectorSettings.showInspectorStack {
                Divider().padding(.vertical, 12)
                stackSection
            }

        case .relationships:
            if showsDeepIntelligence, inspectorSettings.showInspectorRelationships {
                Divider().padding(.vertical, 12)
                relationshipsSection
            }

        case .recommendations:
            if showsDeepIntelligence, inspectorSettings.showInspectorRecommendations {
                Divider().padding(.vertical, 12)
                recommendationsSection
            }
        }
    }

    private var intelligenceFetchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("GitHub Snapshot")

            if let intelligenceActionNotice {
                Text(intelligenceActionNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if catalogSnapshot.status == .ready {
                Text("GitHub metadata is saved locally. Clone only when you want deeper stack analysis, AI summary, or runbooks.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if catalogSnapshot.status.canFetch,
                      IntelligenceRepositoryBridge.resolvedGitHubURL(for: project) != nil {
                Text("Refresh from GitHub to store stars, topics, and description in the local database — no clone required.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(isFetchingIntelligence ? "Refreshing…" : (catalogSnapshot.status == .failed ? "Retry GitHub Refresh" : "Refresh from GitHub")) {
                        fetchIntelligenceFromCatalog()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isFetchingIntelligence)
                }
            } else if catalogSnapshot.status.canFetch,
                      IntelligenceRepositoryBridge.resolvedGitHubURL(for: project) == nil {
                Text("Add a valid GitHub URL before refreshing metadata.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(intelligenceProgressMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button("View Queue") {
                    NotificationCenter.default.post(name: .openQueue, object: nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let error = catalogSnapshot.errorMessage, catalogSnapshot.status == .failed {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private var intelligenceProgressMessage: String {
        switch catalogSnapshot.status {
        case .queued:
            return "Intelligence fetch is queued. Progress appears in Queue."
        case .fetching:
            return "Fetching GitHub metadata."
        case .cloning:
            return "Cloning the repository locally."
        case .analyzing:
            return "Running stack analysis and optional AI enrichment."
        default:
            return "Intelligence work is in progress."
        }
    }

    private func fetchIntelligenceFromCatalog() {
        isFetchingIntelligence = true
        intelligenceActionNotice = nil
        Task {
            let outcome = await CatalogIntelligenceIngestionService.fetchIntelligence(for: project)
            await MainActor.run {
                isFetchingIntelligence = false
                intelligenceActionNotice = inspectFetchOutcomeMessage(outcome)
                catalogSnapshot = CatalogIntelligenceStatusResolver.snapshot(for: project)
            }
            await loadCloneStatus()
        }
    }

    private func cloneLocallyFromInspector() {
        isCloningLocally = true
        cloneActionNotice = nil
        Task {
            let result = await CatalogIntelligenceIngestionService.cloneLocally(for: project)
            await MainActor.run {
                isCloningLocally = false
                switch result {
                case .succeeded:
                    cloneActionNotice = "Clone finished. Stack analysis may continue in the background."
                case .failed(let message):
                    cloneActionNotice = message
                }
                catalogSnapshot = CatalogIntelligenceStatusResolver.snapshot(for: project)
            }
            await loadCloneStatus()
        }
    }

    private func inspectFetchOutcomeMessage(_ outcome: CatalogIntelligenceFetchOutcome) -> String {
        switch outcome {
        case .started:
            return "Intelligence fetch started. Track detailed progress in Queue."
        case .skippedAlreadyReady:
            return "Intelligence is already ready for this project."
        case .skippedInProgress:
            return "Intelligence fetch is already queued or running."
        case .skippedInvalidURL:
            return "This project does not have a valid GitHub URL."
        case .skippedNoGitHubURL:
            return "Add a GitHub URL before fetching intelligence."
        case .failed(let message):
            return "Fetch failed: \(message)"
        }
    }

    // MARK: - Sections

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Metadata")
            if !project.githubURL.isEmpty {
                metadataRow("GitHub", project.githubURL) {
                    if let url = URL(string: project.githubURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if !project.websiteURL.isEmpty {
                metadataRow("Website", project.websiteURL) {
                    if let url = URL(string: project.websiteURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if !project.stars.isEmpty || !project.license.isEmpty {
                HStack(spacing: 6) {
                    if !project.stars.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text(project.stars)
                                .font(.system(size: 11))
                        }
                    }
                    if !project.stars.isEmpty && !project.license.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                    }
                    if !project.license.isEmpty {
                        Text(project.license)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if !project.category.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(project.category)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var localCopySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Local Copy")

            if project.githubURL.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Add a GitHub URL to clone this repo.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if CatalogCloneService.isCloned(project),
                      let dest = CatalogCloneService.destination(for: project) {
                Text(dest.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(dest.path)
                HStack(spacing: 8) {
                    Button("Reveal in Finder") { CatalogCloneService.revealInFinder(dest) }
                        .controlSize(.small)
                    let editors = CatalogCloneService.installedEditors()
                    Menu("Open in…") {
                        ForEach(editors, id: \.name) { editor in
                            Button(editor.name) { CatalogCloneService.open(dest, inEditorAt: editor.appURL) }
                        }
                        Button("Terminal") { CatalogCloneService.openInTerminal(dest) }
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                }
            } else if isCloningLocalCopy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Cloning…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text("Clone a full copy to your repositories folder (\(CloneLocation.rootURL.lastPathComponent)/owner/name).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Clone Repository") { cloneLocalCopy() }
                    .controlSize(.small)
            }

            if let localCopyNotice {
                Text(localCopyNotice)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cloneLocalCopy() {
        isCloningLocalCopy = true
        localCopyNotice = nil
        Task {
            do {
                _ = try await CatalogCloneService.clone(project)
                await MainActor.run {
                    isCloningLocalCopy = false
                }
            } catch {
                await MainActor.run {
                    isCloningLocalCopy = false
                    localCopyNotice = error.localizedDescription
                }
            }
        }
    }

    private var githubMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("GitHub")

            if let githubMetadata {
                if let description = githubMetadata.description,
                   !description.isEmpty,
                   !descriptionDuplicatesCatalog(description) {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }

                if hasGitHubStatsRow(githubMetadata) {
                    HStack(spacing: 8) {
                        if let stars = githubMetadata.stars {
                            Label("\(stars)", systemImage: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if let language = githubMetadata.primaryLanguage, !language.isEmpty {
                            Text(language)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        if let license = githubMetadata.licenseSPDX, !license.isEmpty {
                            Text(license)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                let extraTopics = githubTopicsNotInCatalog(from: githubMetadata)
                if !extraTopics.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(extraTopics, id: \.self) { topic in
                            Text(topic)
                                .font(.system(size: 10))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                    }
                }
            }
        }
    }

    private var shouldShowGitHubMetadataSection: Bool {
        guard let githubMetadata else { return false }
        let hasUniqueDescription = (githubMetadata.description ?? "").isEmpty == false
            && !descriptionDuplicatesCatalog(githubMetadata.description ?? "")
        return hasGitHubStatsRow(githubMetadata)
            || !githubTopicsNotInCatalog(from: githubMetadata).isEmpty
            || hasUniqueDescription
    }

    private func hasGitHubStatsRow(_ metadata: RepositoryMetadataRecord) -> Bool {
        metadata.stars != nil
            || !(metadata.primaryLanguage ?? "").isEmpty
            || !(metadata.licenseSPDX ?? "").isEmpty
    }

    private func descriptionDuplicatesCatalog(_ githubDescription: String) -> Bool {
        let catalog = normalizedComparableText(project.longDescription)
        let github = normalizedComparableText(githubDescription)
        guard !github.isEmpty else { return true }
        guard !catalog.isEmpty else { return false }
        return catalog == github
    }

    private func githubTopicsNotInCatalog(from metadata: RepositoryMetadataRecord) -> [String] {
        let catalogTags = Set(project.tags.map(normalizedComparableText))
        return decodeStringArray(metadata.topicsJSON).filter { topic in
            !catalogTags.contains(normalizedComparableText(topic))
        }
    }

    private func normalizedComparableText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var cloneStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Local Clone")

            if let cloneActionNotice {
                Text(cloneActionNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let cloneSnapshot {
                cloneInfoRow("Status", cloneSnapshot.cloneState.status.capitalized)

                if let path = cloneSnapshot.cloneState.path, !path.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Local path:")
                            .font(.system(size: 11, weight: .medium))
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                    }
                }

                if let error = cloneSnapshot.cloneState.lastError, !error.isEmpty {
                    cloneInfoRow("Last error", error, color: .red)
                }

                if cloneSnapshot.cloneState.status == "not_cloned",
                   IntelligenceRepositoryBridge.resolvedGitHubURL(for: project) != nil {
                    Button(isCloningLocally ? "Cloning…" : "Clone Locally") {
                        cloneLocallyFromInspector()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCloningLocally)
                }
            } else if let cloneStatusError {
                Text(cloneStatusError)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if IntelligenceRepositoryBridge.resolvedGitHubURL(for: project) != nil,
                   catalogSnapshot.status == .ready {
                    Button(isCloningLocally ? "Cloning…" : "Clone Locally") {
                        cloneLocallyFromInspector()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCloningLocally)
                }
            } else {
                Text("Not cloned yet. Refresh from GitHub first, then clone when you want local analysis.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Stack")

            if stackItems.isEmpty {
                Text("No static analysis results yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                let ranked = rankedStackItems
                let preview = Array(ranked.prefix(Self.stackPreviewChipCount))

                FlowLayout(spacing: 6) {
                    ForEach(preview, id: \.id) { item in
                        StackChip(item: item)
                    }
                }

                if ranked.count > preview.count || stackGroups.count > 1 {
                    DisclosureGroup(isExpanded: $showsFullStack) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(stackGroups, id: \.category) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.tertiary)
                                    FlowLayout(spacing: 6) {
                                        ForEach(group.items, id: \.id) { item in
                                            StackChip(item: item)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(showsFullStack ? "Hide full stack" : "Show full stack (\(ranked.count) detected)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: project.id) { _, _ in
            showsFullStack = false
        }
    }

    private static let stackPreviewChipCount = 6

    private var rankedStackItems: [DetectedStackItemRecord] {
        stackItems.sorted { lhs, rhs in
            let lhsRank = stackCategoryRank(lhs.category)
            let rhsRank = stackCategoryRank(rhs.category)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.confidence == rhs.confidence { return lhs.name < rhs.name }
            return lhs.confidence > rhs.confidence
        }
    }

    private func stackCategoryRank(_ category: String) -> Int {
        switch category {
        case "language": return 0
        case "framework": return 1
        case "ai_integration": return 2
        case "runtime": return 3
        case "package_manager": return 4
        case "database": return 5
        case "desktop": return 6
        case "deployment": return 7
        case "local_first": return 8
        case "tooling": return 9
        default: return 10
        }
    }

    private var stackGroups: [(category: String, title: String, items: [DetectedStackItemRecord])] {
        let order = ["language", "framework", "runtime", "package_manager", "database", "ai_integration", "desktop", "deployment", "tooling", "local_first"]
        let grouped = Dictionary(grouping: stackItems) { $0.category }

        return order.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, stackTitle(for: category), items.sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.name < rhs.name
                }
                return lhs.confidence > rhs.confidence
            })
        }
    }

    private var intelligenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Intelligence")

            if let aiInsight, let repositoryScore {
                intelligenceContent(aiInsight: aiInsight, repositoryScore: repositoryScore)
            } else {
                Text("No AI intelligence yet. It will appear after static analysis and local Ollama analysis complete.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func intelligenceContent(aiInsight: AIInsightRecord,
                                     repositoryScore: RepositoryScoreRecord) -> some View {
        let risks = decodeStringArray(aiInsight.risksJSON)
        let classifications = decodeStringArray(aiInsight.classificationsJSON)
        let relationshipHints = decodeStringArray(aiInsight.relationshipHintsJSON)

        return VStack(alignment: .leading, spacing: 10) {
            Text(aiInsight.summary)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.88))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !classifications.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(classifications.prefix(4), id: \.self) { classification in
                        Text(classification)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                            .foregroundStyle(.blue)
                    }
                }
            }

            HStack(spacing: 12) {
                glanceScore(label: "Try it", value: repositoryScore.experimentationPriority)
                glanceScore(label: "Local-first", value: repositoryScore.localFirstScore)
                glanceScore(label: "Relevance", value: repositoryScore.personalRelevance)
            }

            DisclosureGroup(isExpanded: $showsIntelligenceDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorTextBlock(title: "Why It Matters", text: aiInsight.usefulness)

                    if !risks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Risks")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(risks, id: \.self) { risk in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                        .padding(.top, 1)
                                    Text(risk)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("All scores")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        scoreRow("Setup complexity", repositoryScore.setupComplexity, inverse: true)
                        scoreRow("Local-first", repositoryScore.localFirstScore)
                        scoreRow("Experiment priority", repositoryScore.experimentationPriority)
                        scoreRow("Ecosystem influence", repositoryScore.ecosystemInfluence)
                        scoreRow("Personal relevance", repositoryScore.personalRelevance)
                    }

                    if !relationshipHints.isEmpty {
                        inspectorTextBlock(title: "Relationship Hints",
                                           text: relationshipHints.joined(separator: "\n"))
                    }
                }
            } label: {
                Text(showsIntelligenceDetails ? "Hide details" : "More intelligence")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: project.id) { _, _ in
            showsIntelligenceDetails = false
        }
    }

    private func glanceScore(label: String, value: Int) -> some View {
        let clamped = min(10, max(0, value))
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(clamped)/10")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(clamped >= 7 ? .green : .secondary)
        }
    }

    private var relationshipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Relationships")

            if relationships.isEmpty {
                Text("No graph relationships yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                let ranked = rankedRelationships
                let preview = Array(ranked.prefix(Self.relationshipPreviewCount))

                ForEach(preview) { relationship in
                    RelationshipRow(relationship: relationship, compact: true)
                }

                if ranked.count > preview.count {
                    DisclosureGroup(isExpanded: $showsAllRelationships) {
                        ForEach(Array(ranked.dropFirst(preview.count))) { relationship in
                            RelationshipRow(relationship: relationship, compact: false)
                        }
                    } label: {
                        Text("\(showsAllRelationships ? "Hide" : "Show") \(ranked.count - preview.count) more")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: project.id) { _, _ in
            showsAllRelationships = false
        }
    }

    private static let relationshipPreviewCount = 3

    private var rankedRelationships: [GraphRelationshipSummary] {
        relationships.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.targetLabel < rhs.targetLabel
            }
            return lhs.confidence > rhs.confidence
        }
    }

    private var compareActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Compare")

            if let repositoryID = intelligenceRepositoryID, isIntelligenceReady {
                HStack(spacing: 8) {
                    Button("Add to Compare") {
                        CompareDeepLinkNotifier.post(
                            CompareDeepLinkRequest(intent: .addRepository(repositoryID))
                        )
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Menu {
                        Button("Compare Similar") {
                            CompareDeepLinkNotifier.post(
                                CompareDeepLinkRequest(intent: .compareSimilar(sourceRepositoryID: repositoryID))
                            )
                        }
                        Button("Compare Alternatives") {
                            CompareDeepLinkNotifier.post(
                                CompareDeepLinkRequest(intent: .compareAlternatives(sourceRepositoryID: repositoryID))
                            )
                        }
                        Divider()
                        Button("Open Compare View") {
                            NotificationCenter.default.post(name: .openCompare, object: nil)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .help("More compare actions")
                }
            } else {
                Text("Refresh from GitHub to unlock compare.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recommendations")

            if recommendations.isEmpty {
                Text("No recommendations yet. They will appear after relationship generation completes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                let ranked = rankedRecommendations
                let preview = Array(ranked.prefix(Self.recommendationPreviewCount))

                ForEach(preview) { recommendation in
                    RecommendationRow(recommendation: recommendation,
                                      cluster: RepositoryRankingService.clusterLabel(for: recommendation),
                                      signals: decodeStringArray(recommendation.signalsJSON),
                                      sourceRepositoryID: intelligenceRepositoryID)
                }

                if ranked.count > preview.count {
                    DisclosureGroup(isExpanded: $showsAllRecommendations) {
                        ForEach(Array(ranked.dropFirst(preview.count))) { recommendation in
                            RecommendationRow(recommendation: recommendation,
                                              cluster: RepositoryRankingService.clusterLabel(for: recommendation),
                                              signals: decodeStringArray(recommendation.signalsJSON),
                                              sourceRepositoryID: intelligenceRepositoryID)
                        }
                    } label: {
                        Text(showsAllRecommendations ? "Hide" : "Show \(ranked.count - preview.count) more")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: project.id) { _, _ in
            showsAllRecommendations = false
        }
    }

    private static let recommendationPreviewCount = 3

    private var rankedRecommendations: [RepositoryRecommendationSummary] {
        recommendations.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.targetLabel < rhs.targetLabel }
            return lhs.score > rhs.score
        }
    }

    // MARK: - Helpers

    private func useCaseRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 18, height: 18)
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 1)

            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func metadataRow(_ label: String, _ value: String, action: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.system(size: 11, weight: .medium))
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .help(value)
        // Left-click opens the link; right-click copies it.
        .onTapGesture(perform: action)
        .contextMenu {
            Button("Open") { action() }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }

    private func cloneInfoRow(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .font(.system(size: 11, weight: .medium))
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .lineLimit(3)
            Spacer()
        }
    }

    private func inspectorTextBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.82))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scoreRow(_ label: String, _ score: Int, inverse: Bool = false) -> some View {
        let clamped = min(10, max(0, score))
        let valueColor: Color = inverse
            ? (clamped >= 7 ? .orange : .green)
            : (clamped >= 7 ? .green : .secondary)

        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 124, alignment: .leading)
            ProgressView(value: Double(clamped), total: 10)
                .controlSize(.small)
                .tint(valueColor)
            Text("\(clamped)/10")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(valueColor)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 8)
    }

    private func fitLabel(for score: Int) -> String {
        switch score {
        case 1: "Not a fit"
        case 2: "Maybe useful"
        case 3: "Worth exploring"
        case 4: "Very useful"
        case 5: "Essential"
        default: ""
        }
    }

    private func stackTitle(for category: String) -> String {
        switch category {
        case "language":
            return "Languages"
        case "framework":
            return "Frameworks"
        case "runtime":
            return "Runtimes"
        case "package_manager":
            return "Package managers"
        case "database":
            return "Databases"
        case "ai_integration":
            return "AI integrations"
        case "desktop":
            return "Desktop"
        case "deployment":
            return "Deployment"
        case "tooling":
            return "Tooling"
        case "local_first":
            return "Local-first indicators"
        default:
            return category.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func deleteProject() {
        modelContext.delete(project)
        try? modelContext.save()
    }

    private func loadCloneStatus() async {
        let githubURL = project.githubURL
        let projectName = project.name
        let payload = await Task.detached(priority: .userInitiated) {
            InspectDetailLoader.load(githubURL: githubURL, projectName: projectName)
        }.value
        guard !Task.isCancelled else { return }

        catalogSnapshot = payload.catalogSnapshot
        cloneSnapshot = payload.cloneSnapshot
        intelligenceRepositoryID = payload.intelligenceRepositoryID
        githubMetadata = payload.githubMetadata
        stackItems = payload.stackItems
        aiInsight = payload.aiInsight
        repositoryScore = payload.repositoryScore
        relationships = payload.relationships
        recommendations = payload.recommendations
        cloneStatusError = payload.cloneStatusError
    }

    private func decodeStringArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}

private struct InspectDetailLoader {
    struct Payload {
        let catalogSnapshot: CatalogIntelligenceStatusSnapshot
        let cloneSnapshot: CloneStatusSnapshot?
        let intelligenceRepositoryID: String?
        let githubMetadata: RepositoryMetadataRecord?
        let stackItems: [DetectedStackItemRecord]
        let aiInsight: AIInsightRecord?
        let repositoryScore: RepositoryScoreRecord?
        let relationships: [GraphRelationshipSummary]
        let recommendations: [RepositoryRecommendationSummary]
        let cloneStatusError: String?
    }

    static func load(githubURL: String, projectName: String) -> Payload {
        let catalogSnapshot = CatalogIntelligenceStatusResolver.snapshot(githubURL: githubURL,
                                                                         projectName: projectName)
        do {
            try IntelligenceDatabase.shared.initialize()
            guard !githubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return Payload(catalogSnapshot: catalogSnapshot,
                               cloneSnapshot: nil,
                               intelligenceRepositoryID: nil,
                               githubMetadata: nil,
                               stackItems: [],
                               aiInsight: nil,
                               repositoryScore: nil,
                               relationships: [],
                               recommendations: [],
                               cloneStatusError: "No GitHub URL is available for clone tracking.")
            }

            let repository = CatalogIntelligenceStatusResolver.findRepository(githubURL: githubURL,
                                                                              projectName: projectName)

            guard let repository else {
                return Payload(catalogSnapshot: catalogSnapshot,
                               cloneSnapshot: nil,
                               intelligenceRepositoryID: nil,
                               githubMetadata: nil,
                               stackItems: [],
                               aiInsight: nil,
                               repositoryScore: nil,
                               relationships: [],
                               recommendations: [],
                               cloneStatusError: "No intelligence record yet for this GitHub repo.")
            }

            let githubMetadata = try IntelligenceDatabase.shared.fetchMetadata(repositoryID: repository.id)
            let cloneState = try IntelligenceDatabase.shared.fetchCloneState(repositoryID: repository.id)
            let cloneSnapshot = cloneState.map { CloneStatusSnapshot(repository: repository, cloneState: $0) }

            let aiInsight = try IntelligenceDatabase.shared.fetchLatestAIInsight(repositoryID: repository.id)
            let repositoryScore: RepositoryScoreRecord?
            if let aiInsight {
                repositoryScore = try IntelligenceDatabase.shared.fetchRepositoryScore(cacheKey: aiInsight.cacheKey)
            } else {
                repositoryScore = nil
            }

            return Payload(
                catalogSnapshot: catalogSnapshot,
                cloneSnapshot: cloneSnapshot,
                intelligenceRepositoryID: repository.id,
                githubMetadata: githubMetadata,
                stackItems: try IntelligenceDatabase.shared.fetchDetectedStackItems(repositoryID: repository.id),
                aiInsight: aiInsight,
                repositoryScore: repositoryScore,
                relationships: try IntelligenceDatabase.shared.fetchGraphRelationships(repositoryID: repository.id),
                recommendations: try IntelligenceDatabase.shared.fetchRecommendations(repositoryID: repository.id),
                cloneStatusError: nil
            )
        } catch {
            return Payload(catalogSnapshot: catalogSnapshot,
                           cloneSnapshot: nil,
                           intelligenceRepositoryID: nil,
                           githubMetadata: nil,
                           stackItems: [],
                           aiInsight: nil,
                           repositoryScore: nil,
                           relationships: [],
                           recommendations: [],
                           cloneStatusError: error.localizedDescription)
        }
    }
}

private struct StackChip: View {
    let item: DetectedStackItemRecord

    var body: some View {
        Text(item.name)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(chipColor.opacity(0.10))
            )
            .foregroundStyle(chipColor)
            .help(helpText)
    }

    private var chipColor: Color {
        switch item.category {
        case "language":
            return .blue
        case "framework":
            return .purple
        case "runtime":
            return .indigo
        case "package_manager":
            return .cyan
        case "database":
            return .green
        case "ai_integration":
            return .orange
        case "desktop":
            return .teal
        case "deployment":
            return .brown
        case "local_first":
            return .mint
        default:
            return .secondary
        }
    }

    private var helpText: String {
        [item.detectionSource, item.evidencePath, item.evidenceText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct RelationshipRow: View {
    let relationship: GraphRelationshipSummary
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(relationship.targetLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(relationshipSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int((relationship.confidence * 100).rounded()))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(confidenceColor)
            }

            if !compact, let evidence = relationship.evidenceText, !evidence.isEmpty {
                Text(evidence)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, compact ? 2 : 4)
        .help(helpText)
    }

    private var relationshipSubtitle: String {
        relationshipTitle(for: relationship.relationshipType)
    }

    private func relationshipTitle(for type: String) -> String {
        switch type {
        case "similar_to": return "Related"
        case "alternative_to": return "Alternative"
        case "integrates_with": return "Integrates"
        case "useful_for": return "Useful for"
        case "same_stack": return "Shared stack"
        case "same_problem_space": return "Same space"
        case "compatible_with": return "Compatible"
        case "implements_protocol": return "Protocol"
        case "depends_on": return "Depends on"
        default: return type.replacingOccurrences(of: "_", with: " ")
        }
    }

    private var confidenceColor: Color {
        if relationship.confidence >= 0.85 {
            return .green
        }
        if relationship.confidence >= 0.65 {
            return .orange
        }
        return .secondary
    }

    private var helpText: String {
        [
            relationship.relationshipType,
            relationship.createdBy,
            relationship.evidencePath,
            relationship.evidenceText
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

private struct RecommendationRow: View {
    let recommendation: RepositoryRecommendationSummary
    let cluster: String
    let signals: [String]
    var sourceRepositoryID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(recommendation.targetLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.86))
                    .lineLimit(1)
                Text(cluster)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let sourceRepositoryID {
                    if let targetRepositoryID = recommendationTargetRepositoryID {
                        Button("Compare") {
                            CompareDeepLinkNotifier.post(
                                CompareDeepLinkRequest(intent: .compare(repositoryIDs: [sourceRepositoryID, targetRepositoryID]))
                            )
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                    }
                }
                Text("\(Int(recommendation.score.rounded()))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(scoreColor)
            }

            Text(recommendation.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let firstSignal = signals.first {
                Text(firstSignal)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.045))
        )
        .help(helpText)
    }

    private var recommendationTargetRepositoryID: String? {
        guard recommendation.targetKey.hasPrefix("repository:") else { return nil }
        return String(recommendation.targetKey.dropFirst("repository:".count))
    }

    private var scoreColor: Color {
        if recommendation.score >= 75 {
            return .green
        }
        if recommendation.score >= 55 {
            return .orange
        }
        return .secondary
    }

    private var helpText: String {
        [
            recommendation.recommendationType.replacingOccurrences(of: "_", with: " "),
            recommendation.explanation,
            signals.joined(separator: " · ")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }
}

private struct CloneStatusSnapshot: Equatable {
    let repository: RepositoryRecord
    let cloneState: CloneStateRecord
}

struct EmptyInspectorView: View {
    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                HStack {
                    Text("Inspector")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            ContentUnavailableView(
                "No Item Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a project to inspect its details.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
