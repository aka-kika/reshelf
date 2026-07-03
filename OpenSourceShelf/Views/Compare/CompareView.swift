import SwiftUI

@Observable
@MainActor
final class CompareScreenModel {
    var selectedRepositoryIDs: [String] = []
    var searchQuery: String = ""
    var searchResults: [RepositoryRecord] = []
    var candidates: [CompareFocusCandidate] = []
    var recentSessions: [ComparisonSessionRecord] = []
    var favoriteSessions: [ComparisonSessionRecord] = []
    var sessionFilter: ComparisonSessionFilter = .recent
    var activePreset: ComparisonPreset?
    var presetCandidates: [ComparisonPresetCandidate] = []
    var result: RepositoryComparisonResult?
    var selectedRankingRepositoryID: String?
    var isLoading = false
    var errorMessage: String?
    var statusMessage: String?
    var pendingRunbookRepositoryID: String?

    var displayedSessions: [ComparisonSessionRecord] {
        switch sessionFilter {
        case .recent:
            return recentSessions
        case .favorites:
            return favoriteSessions
        }
    }

    func bootstrap() async {
        do {
            candidates = try RepositoryCompareService.fetchCandidates()
            await reloadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadSessions() async {
        do {
            recentSessions = try RepositoryCompareService.recentSessions()
            favoriteSessions = try RepositoryCompareService.favoriteSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try RepositoryCompareService.searchRepositories(query: query)
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
    }

    func toggleSelection(_ repositoryID: String) {
        if let index = selectedRepositoryIDs.firstIndex(of: repositoryID) {
            selectedRepositoryIDs.remove(at: index)
            if selectedRankingRepositoryID == repositoryID {
                selectedRankingRepositoryID = nil
            }
            return
        }
        guard selectedRepositoryIDs.count < RepositoryCompareService.maxRepositories else { return }
        selectedRepositoryIDs.append(repositoryID)
    }

    func loadSession(_ repositoryIDs: [String]) {
        selectedRepositoryIDs = Array(repositoryIDs.prefix(RepositoryCompareService.maxRepositories))
        result = nil
        selectedRankingRepositoryID = nil
        Task { await runComparison() }
    }

    func toggleFavorite(_ session: ComparisonSessionRecord) {
        do {
            try RepositoryCompareService.setSessionFavorite(sessionID: session.id, isFavorite: !session.isFavorite)
            Task { await reloadSessions() }
            statusMessage = session.isFavorite ? "Removed from favorites." : "Saved to favorites."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPreset(_ preset: ComparisonPreset) {
        activePreset = preset
        do {
            presetCandidates = try ComparisonPresetService.suggestCandidates(for: preset)
            if presetCandidates.isEmpty {
                statusMessage = "No strong matches for \(preset.rawValue) yet. Try ingesting more repos."
            }
        } catch {
            errorMessage = error.localizedDescription
            presetCandidates = []
        }
    }

    func clearPreset() {
        activePreset = nil
        presetCandidates = []
    }

    func runComparison() async {
        guard selectedRepositoryIDs.count >= RepositoryCompareService.minRepositories else {
            errorMessage = RepositoryCompareError.invalidSelection.errorDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            result = try await RepositoryCompareService.buildComparison(repositoryIDs: selectedRepositoryIDs)
            await reloadSessions()
            selectedRankingRepositoryID = result?.rankings.first?.repositoryID
            AppRefreshBus.emit(.comparisonUpdated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyDeepLink(_ request: CompareDeepLinkRequest) async {
        errorMessage = nil
        switch request.intent {
        case let .compare(repositoryIDs):
            selectedRepositoryIDs = Array(Set(repositoryIDs)).sorted().prefix(RepositoryCompareService.maxRepositories).map { $0 }
            await runComparison()
        case let .addRepository(repositoryID):
            toggleSelection(repositoryID)
            statusMessage = "Added to compare selection."
        case let .compareSimilar(sourceRepositoryID):
            do {
                selectedRepositoryIDs = try RepositoryCompareService.repositoryIDsForSimilar(sourceRepositoryID: sourceRepositoryID)
                await runComparison()
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .compareAlternatives(sourceRepositoryID):
            do {
                selectedRepositoryIDs = try RepositoryCompareService.repositoryIDsForAlternatives(sourceRepositoryID: sourceRepositoryID)
                await runComparison()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func copySummary() {
        guard let result else { return }
        ComparisonExportService.copyToPasteboard(ComparisonExportService.copySummary(for: result))
        statusMessage = "Decision summary copied."
    }

    func copyMarkdown() {
        guard let result else { return }
        ComparisonExportService.copyToPasteboard(ComparisonExportService.markdown(for: result))
        statusMessage = "Markdown copied to clipboard."
    }

    func exportMarkdown() {
        guard let result else { return }
        let markdown = ComparisonExportService.markdown(for: result)
        let filename = ComparisonExportService.defaultFilename(for: result)
        ComparisonExportService.saveMarkdown(markdown, suggestedFilename: filename)
        statusMessage = "Export ready."
    }

    func generateRunbookForWinner() {
        guard let winnerID = selectedRanking?.repositoryID ?? result?.rankings.first?.repositoryID else {
            errorMessage = "Run a comparison and pick a winner first."
            return
        }
        errorMessage = nil
        do {
            _ = try RepositoryRunbookService.enqueueGeneration(repositoryID: winnerID, force: false)
            pendingRunbookRepositoryID = winnerID
            let name = selectedRanking?.fullName ?? result?.rankings.first?.fullName ?? "winner"
            statusMessage = "Runbook generation started for \(name)."
            AppRefreshBus.emit(.queueUpdated)
            AppRefreshBus.emit(.catalogStateUpdated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openWinnerRunbook() {
        guard let repositoryID = pendingRunbookRepositoryID ?? winnerRepositoryID else { return }
        RunbookDeepLinkNotifier.post(RunbookDeepLinkRequest(repositoryID: repositoryID))
        statusMessage = nil
    }

    var winnerRepositoryID: String? {
        selectedRanking?.repositoryID ?? result?.rankings.first?.repositoryID
    }

    var selectedRanking: ComparisonRankingEntry? {
        guard let selectedRankingRepositoryID, let result else { return nil }
        return result.rankings.first { $0.repositoryID == selectedRankingRepositoryID }
    }

    var currentSessionID: String? {
        guard selectedRepositoryIDs.count >= RepositoryCompareService.minRepositories else { return nil }
        return RepositoryCompareService.sessionID(for: selectedRepositoryIDs)
    }

    func toggleCurrentSessionFavorite() {
        guard let sessionID = currentSessionID else { return }
        let isFavorite = favoriteSessions.contains(where: { $0.id == sessionID })
        do {
            try RepositoryCompareService.setSessionFavorite(sessionID: sessionID, isFavorite: !isFavorite)
            Task { await reloadSessions() }
            statusMessage = isFavorite ? "Removed from favorites." : "Saved to favorites."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var isCurrentSessionFavorite: Bool {
        guard let sessionID = currentSessionID else { return false }
        return favoriteSessions.contains(where: { $0.id == sessionID })
    }
}

struct CompareView: View {
    @Bindable var model: CompareScreenModel
    /// When true (or no result yet) the main area shows the repo picker; running a
    /// comparison flips it to the results view.
    @State private var editingSelection = false

    private var showingSelection: Bool {
        model.result == nil || editingSelection
    }

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                HStack(spacing: 8) {
                    Text("Compare")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if !showingSelection {
                        Button(action: { model.toggleCurrentSessionFavorite() }) {
                            Image(systemName: model.isCurrentSessionFavorite ? "star.fill" : "star")
                                .foregroundStyle(model.isCurrentSessionFavorite ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Favorite this comparison")
                        .titlebarClickable { model.toggleCurrentSessionFavorite() }

                        Menu {
                            Button("Copy Summary") { model.copySummary() }
                            Button("Copy Markdown") { model.copyMarkdown() }
                            Button("Export as Markdown…") { model.exportMarkdown() }
                            if model.winnerRepositoryID != nil {
                                Divider()
                                Button("Generate Runbook for Winner") {
                                    model.generateRunbookForWinner()
                                }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Export comparison")
                        .titlebarClickable()
                    }

                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else if showingSelection {
                        Button("Run comparison") {
                            editingSelection = false
                            Task { await model.runComparison() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedRepositoryIDs.count < RepositoryCompareService.minRepositories)
                        .controlSize(.small)
                        .titlebarClickable {
                            guard model.selectedRepositoryIDs.count >= RepositoryCompareService.minRepositories else { return }
                            editingSelection = false
                            Task { await model.runComparison() }
                        }
                    } else {
                        Button {
                            editingSelection = true
                        } label: {
                            Label("Edit Repos", systemImage: "slider.horizontal.3")
                        }
                        .controlSize(.small)
                        .help("Change the repositories being compared")
                        .titlebarClickable { editingSelection = true }
                    }
                }
            }

            if let status = model.statusMessage {
                HStack {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if model.pendingRunbookRepositoryID != nil {
                        Button("Open Runbook") {
                            model.openWinnerRunbook()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    Button("Dismiss") { model.statusMessage = nil }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
            }

            ScrollView {
                if let error = model.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(16)
                }

                if showingSelection {
                    selectionArea
                } else if let result = model.result {
                    comparisonContent(result)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: AppRefreshBus.notificationName)) { notification in
            guard let event = AppRefreshEvent.decode(from: notification),
                  case let .runbookGenerated(completedID) = event,
                  completedID == model.pendingRunbookRepositoryID else { return }
            model.statusMessage = "Runbook ready. Open Runbook to review suggested commands."
        }
    }

    /// Repo picker shown directly in the main area (selection mode). Running a
    /// comparison from the header replaces it with the results view; "Edit Repos"
    /// brings it back. Centered with a comfortable max width so it reads like a
    /// focused panel rather than a stretched list.
    private var selectionArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.selectedRepositoryIDs.count >= RepositoryCompareService.minRepositories
                    ? "Ready to compare \(model.selectedRepositoryIDs.count) repositories — press Run comparison."
                    : "Pick 2–\(RepositoryCompareService.maxRepositories) repositories, then press Run comparison.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 14)

            ComparePickerView(
                selectedRepositoryIDs: $model.selectedRepositoryIDs,
                candidates: model.candidates,
                sessions: model.displayedSessions,
                sessionFilter: $model.sessionFilter,
                searchQuery: $model.searchQuery,
                searchResults: model.searchResults,
                presetCandidates: model.presetCandidates,
                activePreset: model.activePreset,
                maxSelection: RepositoryCompareService.maxRepositories,
                onSearch: { model.search() },
                onSelectCandidate: { model.toggleSelection($0) },
                onLoadSession: { model.loadSession($0) },
                onToggleFavorite: { model.toggleFavorite($0) },
                onSelectPreset: { model.loadPreset($0) },
                onClearPreset: { model.clearPreset() }
            )
        }
        .frame(maxWidth: 600, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func comparisonContent(_ result: RepositoryComparisonResult) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            winnerHero(result)

            rankingSection(result)

            CompareMatrixView(result: result)

            if !result.decisionSummary.isEmpty {
                cardSection("Decision summary") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.decisionSummary) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.category)
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(line.winnerLabel): \(line.explanation)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            detailCards(result)
        }
        .padding(16)
    }

    // MARK: - Winner hero

    @ViewBuilder
    private func winnerHero(_ result: RepositoryComparisonResult) -> some View {
        if let winner = result.rankings.first {
            let overall = result.decisionSummary.first { $0.category.lowercased().contains("overall") }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                    Text("Recommended")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Score \(Int(winner.compositeScore.rounded()))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(winner.fullName)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(overall?.explanation ?? winner.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !winner.strongestSignals.isEmpty {
                    chipRow(winner.strongestSignals, tint: .accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1))
        }
    }

    // MARK: - Ranking cards

    private func rankingSection(_ result: RepositoryComparisonResult) -> some View {
        cardSection("Ranking") {
            VStack(spacing: 8) {
                ForEach(result.rankings) { ranking in
                    Button {
                        model.selectedRankingRepositoryID = ranking.repositoryID
                    } label: {
                        rankingRow(ranking, maxScore: maxScore(result))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rankingRow(_ ranking: ComparisonRankingEntry, maxScore: Double) -> some View {
        let selected = model.selectedRankingRepositoryID == ranking.repositoryID
        let isWinner = ranking.rank == 1
        return HStack(spacing: 12) {
            Text("#\(ranking.rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isWinner ? Color.accentColor : .secondary)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(ranking.fullName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(ranking.compositeScore.rounded()))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                scoreBar(ranking.compositeScore, maxScore: maxScore, highlighted: isWinner)
                Text(ranking.explanation)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03)))
        .overlay(selected
            ? RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
            : nil)
        .contentShape(Rectangle())
    }

    private func scoreBar(_ value: Double, maxScore: Double, highlighted: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(highlighted ? Color.accentColor : Color.secondary.opacity(0.7))
                    .frame(width: maxScore > 0
                        ? geo.size.width * CGFloat(min(value / maxScore, 1))
                        : 0)
            }
        }
        .frame(height: 5)
    }

    private func maxScore(_ result: RepositoryComparisonResult) -> Double {
        max(result.rankings.map(\.compositeScore).max() ?? 1, 1)
    }

    // MARK: - Detail cards

    @ViewBuilder
    private func detailCards(_ result: RepositoryComparisonResult) -> some View {
        cardSection("Stack overlap") {
            if result.sharedStack.isEmpty && result.uniqueStack.values.allSatisfy(\.isEmpty) {
                emptyDetail("No stack data yet.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !result.sharedStack.isEmpty {
                        labeledChips("Shared", items: result.sharedStack)
                    }
                    ForEach(result.uniqueStack.keys.sorted(), id: \.self) { repositoryID in
                        if let items = result.uniqueStack[repositoryID], !items.isEmpty,
                           let name = result.profiles.first(where: { $0.repositoryID == repositoryID })?.fullName {
                            labeledChips("Unique to \(name)", items: items)
                        }
                    }
                }
            }
        }

        cardSection("At a glance") {
            VStack(spacing: 0) {
                metricRow("Local-first", result.profiles, keyPath: \.localFirstScore)
                Divider()
                metricRow("Setup complexity", result.profiles, keyPath: \.setupComplexity)
                Divider()
                metricRow("Recommendation signals", result.profiles, keyPath: \.recommendationCount)
            }
        }

        let hasRisks = result.profiles.contains { !$0.risks.isEmpty }
        if hasRisks {
            cardSection("Risks") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.profiles) { profile in
                        if !profile.risks.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.fullName)
                                    .font(.system(size: 11, weight: .medium))
                                ForEach(profile.risks.prefix(4), id: \.self) { risk in
                                    Text("· \(risk)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }

        if !result.graphOverlap.sharedNeighbors.isEmpty
            || !result.graphOverlap.pairPaths.isEmpty
            || !result.graphOverlap.alternativeLinks.isEmpty {
            cardSection("Graph overlap") {
                VStack(alignment: .leading, spacing: 8) {
                    if !result.graphOverlap.sharedNeighbors.isEmpty {
                        labeledChips("Shared neighbors", items: result.graphOverlap.sharedNeighbors)
                    }
                    ForEach(result.graphOverlap.pairPaths) { path in
                        Text("\(path.fromLabel) ↔ \(path.toLabel): \(path.hopCount) hops — \(path.explanation)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if !result.graphOverlap.alternativeLinks.isEmpty {
                        labeledChips("Alternative links", items: result.graphOverlap.alternativeLinks)
                    }
                }
            }
        }

        if !result.sharedEcosystems.isEmpty || result.profiles.contains(where: { !$0.ecosystemNames.isEmpty }) {
            cardSection("Ecosystem fit") {
                VStack(alignment: .leading, spacing: 8) {
                    if !result.sharedEcosystems.isEmpty {
                        labeledChips("Shared ecosystems", items: result.sharedEcosystems)
                    }
                    ForEach(result.profiles) { profile in
                        if !profile.ecosystemNames.isEmpty {
                            labeledChips(profile.fullName, items: profile.ecosystemNames)
                        }
                    }
                }
            }
        }
    }

    /// A per-repo metric row: label on the left, one value per repository.
    private func metricRow(_ label: String,
                           _ profiles: [RepositoryComparisonProfile],
                           keyPath: KeyPath<RepositoryComparisonProfile, Int?>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            ForEach(profiles) { profile in
                Text(profile[keyPath: keyPath].map { "\($0)" } ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }

    private func metricRow(_ label: String,
                           _ profiles: [RepositoryComparisonProfile],
                           keyPath: KeyPath<RepositoryComparisonProfile, Int>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            ForEach(profiles) { profile in
                Text("\(profile[keyPath: keyPath])")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }

    private func emptyDetail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    /// Rounded card wrapper for a titled section.
    private func cardSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
    }

    private func chipRow(_ items: [String], tint: Color) -> some View {
        FlowLayout(spacing: 5) {
            ForEach(items.prefix(8), id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.14)))
                    .foregroundStyle(tint)
            }
        }
    }

    private func labeledChips(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 5) {
                ForEach(items.prefix(12), id: \.self) { item in
                    Text(item)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
    }

}
