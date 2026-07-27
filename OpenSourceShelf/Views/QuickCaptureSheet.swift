import SwiftUI
import SwiftData

struct QuickCaptureSheet: View {
    @Binding var isPresented: Bool
    var onSave: (ToolProject) -> Void
    var initialURL: String = ""

    @Environment(\.modelContext) private var modelContext
    @AppStorage(LabsFeatures.storageKey) private var labsFeaturesEnabled = false
    @AppStorage(CaptureAssist.storageKey) private var captureAssistEnabled = true
    @AppStorage(CaptureAssist.autoGenerateKey) private var captureAutoGenerate = true
    @Query private var existingProjects: [ToolProject]

    @State private var urlText: String = ""
    @State private var isFetching: Bool = false
    @State private var errorMessage: String?
    @State private var fetchedInfo: GitHubRepoInfo?
    @State private var isGeneratingAI: Bool = false
    @State private var aiSuggestion: String = ""
    @State private var hasGeneratedAISuggestion: Bool = false
    /// Last values the on-device model wrote, so Re-generate can safely
    /// overwrite its own fills without touching user edits.
    @State private var lastAIUseCases: String = ""
    @State private var lastAINote: String = ""
    /// Ollama reachability, only meaningful when the resolved provider is Ollama.
    /// nil = not checked / not applicable, true/false = last ping result.
    @State private var ollamaReachable: Bool? = nil
    @State private var isCheckingAI: Bool = false

    // Editable fields after fetch
    @State private var name: String = ""
    @State private var shortDescription: String = ""
    @State private var longDescription: String = ""
    @State private var websiteURL: String = ""
    @State private var category: String = ""
    @State private var status: ProjectStatus = .collector
    @State private var tagsText: String = ""
    @State private var useCasesText: String = ""
    @State private var notes: String = ""
    /// Human-only; Capture Assist never fills this.
    @State private var personalNote: String = ""
    @State private var fitScore: Int = 3
    @State private var stars: String = ""
    @State private var license: String = ""
    /// GitHub's `pushed_at` for the fetched repo — carried into the saved
    /// project so the list can sort by upstream activity.
    @State private var lastUpdatedDate: Date?
    @State private var isLocalFirst: Bool = false
    @State private var isSelfHosted: Bool = false
    /// The rarely-touched fields live behind this disclosure — capture is
    /// paste → Enter → Enter, so the default view is just the card + two decisions.
    @State private var showsMoreDetails: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Quick Capture")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless).font(.system(size: 13))
                if fetchedInfo != nil {
                    Button("Save") { saveProject() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small).font(.system(size: 13))
                        .disabled(name.isEmpty || duplicateProject != nil)
                        // Return saves once a repo is fetched, so ⌘K → paste →
                        // Enter (fetch) → Enter (save) needs no mouse.
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // URL input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GITHUB URL")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TextField("https://github.com/owner/repo", text: $urlText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .onSubmit { handleSubmit() }
                            Button(action: fetchRepo) {
                                if isFetching {
                                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                                } else {
                                    Text("Fetch")
                                        .font(.system(size: 12, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(urlText.isEmpty || isFetching)
                        }
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 11)).foregroundStyle(.red)
                        }
                    }

                    if let dup = duplicateProject {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                            Text("“\(dup.name)” is already in your catalog — saving is disabled to avoid a duplicate.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.08)))
                    }

                    if let info = fetchedInfo {
                        repoCard(info)

                        // The only two decisions worth making at capture time.
                        HStack(alignment: .top, spacing: 16) {
                            field("Shelf") {
                                Picker("", selection: $status) {
                                    ForEach(ProjectStatus.allCases, id: \.self) { s in
                                        Text(s.displayName).tag(s)
                                    }
                                }
                                .pickerStyle(.menu).labelsHidden().fixedSize()
                            }
                            field("Category") {
                                TextField("e.g. Database, AI", text: $category)
                            }
                        }

                        field("Why") {
                            TextField("Why you're saving this (optional)", text: $personalNote)
                        }

                        moreDetailsDisclosure
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: sheetHeight)
        .animation(.easeInOut(duration: 0.2), value: sheetHeight)
        .onAppear {
            if !initialURL.isEmpty {
                urlText = initialURL
                fetchRepo()
            }
        }
    }

    /// Short before fetch, card-sized after, taller when details are expanded.
    private var sheetHeight: CGFloat {
        if fetchedInfo == nil { return 240 }
        return showsMoreDetails ? 740 : 600
    }

    /// The repo the way the shelf will remember it: identity + facts, not fields.
    private func repoCard(_ info: GitHubRepoInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: ownerAvatarURL) { image in
                    image.resizable().interpolation(.high)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(0.06))
                        .overlay {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Repository" : name)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    if let owner = repoOwner {
                        Text(owner)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                if !stars.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text(stars)
                    }
                }
                HStack(spacing: 4) {
                    Text(displayLicense)
                    LicenseInfoButton(license: license)
                }
                if let language = info.language, !language.isEmpty {
                    Text(language)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if !shortDescription.isEmpty {
                Text(shortDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let site = URL(string: websiteURL), !websiteURL.isEmpty {
                Link(destination: site) {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 9))
                        Text(websiteURL
                            .replacingOccurrences(of: "https://", with: "")
                            .replacingOccurrences(of: "http://", with: ""))
                            .lineLimit(1)
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
    }

    /// "owner" from the fetched full name (or the pasted URL as a fallback).
    private var repoOwner: String? {
        if let full = fetchedInfo?.fullName, full.contains("/") {
            return full.components(separatedBy: "/").first
        }
        let parts = urlText
            .replacingOccurrences(of: "https://github.com/", with: "")
            .split(separator: "/")
        return parts.first.map(String.init)
    }

    private var ownerAvatarURL: URL? {
        repoOwner.flatMap { URL(string: "https://github.com/\($0).png?size=64") }
    }

    /// The card shows a human license, never raw SPDX noise.
    private var displayLicense: String {
        let cleaned = license.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty || cleaned.uppercased() == "NOASSERTION" { return "No license" }
        return cleaned
    }

    /// Rarely-touched fields, collapsed by default — capture stays two Enters.
    /// A plain button + chevron instead of DisclosureGroup: on macOS the group
    /// only toggles from its tiny chevron, and the whole row should be tappable.
    private var moreDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsMoreDetails.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showsMoreDetails ? 90 : 0))
                    Text("More details")
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsMoreDetails {
                detailFields
            }
        }
    }

    private var detailFields: some View {
            VStack(alignment: .leading, spacing: 14) {
                // AI suggestions stay zero-setup: in the catalog-only default they
                // appear only when Capture Assist is on and on-device Apple
                // Intelligence is available (no keys, no config). Labs mode adds
                // the configurable providers.
                if labsFeaturesEnabled
                    || (captureAssistEnabled && AppleIntelligenceService.availability.isAvailable) {
                    aiSuggestionsSection
                }
                field("Name") { TextField("", text: $name) }
                field("Links") {
                    TextField("GitHub URL", text: $urlText)
                    TextField("Website URL", text: $websiteURL)
                }
                field("Description") {
                    TextField("Short description", text: $shortDescription)
                    TextEditor(text: $longDescription).frame(height: 60)
                        .overlay(alignment: .topLeading) {
                            if longDescription.isEmpty {
                                Text("Long description…").font(.system(size: 12))
                                    .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                field("Use Cases") {
                    Text("One per line.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                    TextEditor(text: $useCasesText).frame(height: 60)
                }
                field("Tags") {
                    TextField("Comma-separated", text: $tagsText)
                }
                field("Quick Flags") {
                    Toggle("Self-Hosted", isOn: $isSelfHosted)
                    Toggle("Local-First", isOn: $isLocalFirst)
                }
                field("Personal Fit") {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= fitScore ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundStyle(i <= fitScore ? .yellow : .secondary.opacity(0.3))
                                .onTapGesture { fitScore = i }
                        }
                        Text(fitLabel(fitScore)).font(.system(size: 11))
                            .foregroundStyle(.secondary).padding(.leading, 6)
                    }
                }
            }
            .padding(.top, 10)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
        .textFieldStyle(.roundedBorder).font(.system(size: 13))
        .toggleStyle(.checkbox)
    }

    private var aiSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.system(size: 12))
                Text("AI Suggestions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if hasGeneratedAISuggestion {
                    Text("Generated")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
                Spacer()
                if isGeneratingAI || isCheckingAI {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                } else {
                    Button(hasGeneratedAISuggestion ? "Re-generate" : "Generate with AI") {
                        generateAI()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundStyle(aiAvailable ? .purple : .secondary)
                    .disabled(!aiAvailable)
                }
            }

            if let unavailable = aiUnavailableReason {
                Label(unavailable, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if effectiveAIProvider == .appleIntelligence {
                Text("Fills use cases, a note, and tags on-device with Apple Intelligence. Nothing leaves this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Use AI for notes, use cases, and quick flag hints.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if !aiSuggestion.isEmpty {
                Text(aiSuggestion)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.purple.opacity(0.04))
                    )
            }
        }
    }

    private func fitLabel(_ score: Int) -> String {
        switch score {
        case 1: "Not a fit"; case 2: "Maybe useful"
        case 3: "Worth exploring"; case 4: "Very useful"
        case 5: "Essential"; default: ""
        }
    }

    // MARK: - Fetch GitHub Data

    /// Return-key handler: fetch when nothing is fetched yet, otherwise save.
    /// Keeps the whole capture keyboard-only (paste → Enter → Enter).
    private func handleSubmit() {
        if fetchedInfo == nil {
            fetchRepo()
        } else if !name.isEmpty {
            saveProject()
        }
    }

    private func fetchRepo() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isFetching = true; errorMessage = nil

        Task {
            do {
                let info = try await QuickCaptureService.fetchRepoInfo(githubURL: trimmed)
                await MainActor.run {
                    fetchedInfo = info
                    populateFields(from: info, url: trimmed)
                    isFetching = false
                    // The AI section appears now — pre-flight the active provider so
                    // "Generate with AI" reflects offline/unconfigured state.
                    checkAIReachability()
                    // Auto-fetch icon
                    if !name.isEmpty {
                        let temp = ToolProject(name: name, githubURL: trimmed)
                        IconFetcher.fetch(for: temp, in: modelContext)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isFetching = false
                }
            }
        }
    }

    private func populateFields(from info: GitHubRepoInfo, url: String) {
        aiSuggestion = ""
        hasGeneratedAISuggestion = false
        lastAIUseCases = ""
        lastAINote = ""
        name = info.fullName?.components(separatedBy: "/").last ?? name
        shortDescription = info.description ?? ""
        longDescription = info.description ?? ""
        websiteURL = info.homepage ?? ""
        stars = info.stars.map { formatStars($0) } ?? ""
        license = info.license?.spdxId ?? info.license?.name ?? ""
        lastUpdatedDate = info.pushedAt.flatMap(GitHubDate.parse)
        tagsText = info.topics?.joined(separator: ", ") ?? ""

        // Auto-classify category from language, topics, and description
        category = CategoryClassifier.classify(
            language: info.language,
            topics: info.topics,
            description: info.description,
            name: info.fullName?.components(separatedBy: "/").last
        )

        if let topics = info.topics {
            if topics.contains("self-hosted") { isSelfHosted = true }
            if topics.contains("local-first") { isLocalFirst = true }
        }
        // New captures land in The Collector by default — you decide what gets
        // promoted to Top Shelf or sent to the Yard Sale.
    }

    private func formatStars(_ count: Int) -> String {
        if count >= 1000 { return String(format: "%.1fk", Double(count) / 1000.0) }
        return "\(count)"
    }

    // MARK: - AI Generation

    /// Whether "Generate with AI" can run with the user's current provider config.
    private var aiAvailable: Bool { aiUnavailableReason == nil }

    /// reshelf generates on-device and nowhere else. There is no provider to pick.
    private var effectiveAIProvider: AIProviderKind { .appleIntelligence }

    /// User-facing reason the AI step is disabled, or `nil` when it's ready.
    /// Provider-aware: covers Apple Intelligence availability and (for Ollama)
    /// an unreachable local server.
    private var aiUnavailableReason: String? {
        switch effectiveAIProvider {
        case .appleIntelligence:
            let status = AppleIntelligenceService.availability
            return status.isAvailable ? nil : status.label
        case .ollama:
            let settings = AppSettings.current(in: modelContext)
            if ollamaReachable == false {
                return "Ollama isn't running at \(settings.ollamaBaseURL). Start it, or pick another provider in Settings."
            }
            return nil
        case .openAI, .anthropic, .gemini, .githubCopilot:
            return nil
        }
    }

    /// Pre-flights the active provider so the AI button reflects offline state
    /// before the user clicks. Only Ollama needs a reachability ping; Apple
    /// Intelligence and cloud providers surface errors on use.
    private func checkAIReachability() {
        let settings = AppSettings.current(in: modelContext)
        guard effectiveAIProvider == .ollama,
              settings.isConfigured(.ollama) else {
            ollamaReachable = nil
            return
        }
        isCheckingAI = true
        let baseURL = settings.ollamaBaseURL
        Task {
            let reachable = await OllamaService.testConnection(baseURL: baseURL)
            await MainActor.run {
                ollamaReachable = reachable
                isCheckingAI = false
            }
        }
    }

    private func generateAI() {
        guard !name.isEmpty, aiAvailable else { return }
        isGeneratingAI = true

        if effectiveAIProvider == .appleIntelligence {
            generateWithAppleIntelligence()
            return
        }

        let settings = AppSettings.current(in: modelContext)
        let prompt = buildAIPrompt()
        Task {
            let result = await AICompletionService.generate(prompt: prompt, settings: settings)
            await MainActor.run {
                // AICompletionService returns a "Could not reach Ollama" string on a
                // failed local connection — reflect that in button availability.
                if result.contains("Could not reach Ollama") {
                    ollamaReachable = false
                } else {
                    if AICompletionService.resolvedProvider(settings: settings) == .ollama {
                        ollamaReachable = true
                    }
                    hasGeneratedAISuggestion = true
                    applyAISuggestionHints(result)
                }
                aiSuggestion = result
                isGeneratingAI = false
            }
        }
    }

    /// On-device path: guided generation fills the capture fields directly —
    /// use cases, note, tags, and quick flags — instead of a text blob.
    private func generateWithAppleIntelligence() {
        let prompt = """
        Project: \(name)
        Description: \(shortDescription)
        Long description: \(longDescription)
        Category: \(category)
        GitHub stars: \(stars)
        License: \(license)
        Existing tags: \(tagsText)
        """
        Task {
            do {
                let suggestion = try await AppleIntelligenceService.suggestCapture(prompt: prompt)
                await MainActor.run {
                    applyCaptureSuggestion(suggestion)
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiSuggestion = "⚠️ Apple Intelligence: \(error.localizedDescription)"
                    isGeneratingAI = false
                }
            }
        }
    }

    /// Fills empty fields (or re-fills ones still holding the previous AI values,
    /// so Re-generate works) without clobbering anything the user typed.
    private func applyCaptureSuggestion(_ suggestion: AppleIntelligenceService.CaptureSuggestion) {
        let currentUseCases = useCasesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentUseCases.isEmpty || currentUseCases == lastAIUseCases {
            useCasesText = suggestion.useCases.joined(separator: "\n")
            lastAIUseCases = useCasesText
        }
        let currentNotes = notes.trimmingCharacters(in: .whitespaces)
        if currentNotes.isEmpty || currentNotes == lastAINote {
            notes = suggestion.note.trimmingCharacters(in: .whitespaces)
            lastAINote = notes
        }
        let existingTags = Set(tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let newTags = suggestion.tags
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !existingTags.contains($0.lowercased()) }
        if !newTags.isEmpty {
            let base = tagsText.trimmingCharacters(in: .whitespaces)
            tagsText = base.isEmpty ? newTags.joined(separator: ", ")
                                    : base + ", " + newTags.joined(separator: ", ")
        }
        if suggestion.isLocalFirst { isLocalFirst = true }
        if suggestion.isSelfHosted { isSelfHosted = true }
        hasGeneratedAISuggestion = true
        aiSuggestion = "Filled use cases, note, and tags on-device. Edit anything before saving."
    }

    private func buildAIPrompt() -> String {
        """
        You are analyzing an open-source project for a developer's personal toolkit database.

        Project: \(name)
        Description: \(shortDescription)
        Category: \(category)
        GitHub Stars: \(stars)
        License: \(license)
        Tags: \(tagsText)

        Please provide:
        1. 3-5 practical use cases for a developer/maker (one per line, starting with "- ")
        2. A personal fit assessment (1-5) with brief reasoning
        3. 2-3 additional tags that would be useful
        4. A 1-2 sentence personal note about why this tool is worth tracking

        Keep it concise. Format as plain text.
        """
    }

    private func applyAISuggestionHints(_ text: String) {
        let lowercased = text.lowercased()
        if lowercased.contains("local-first") || lowercased.contains("local first") || lowercased.contains("runs locally") {
            isLocalFirst = true
        }
        if lowercased.contains("self-hosted") || lowercased.contains("self hosted") || lowercased.contains("self host") {
            isSelfHosted = true
        }
    }

    /// An existing catalog entry for the same repo being captured, if any — used to
    /// block duplicate saves and warn the user.
    private var duplicateProject: ToolProject? {
        let key = IconFetcher.repoDedupKey(for: urlText)
        guard !key.isEmpty else { return nil }
        return existingProjects.first { IconFetcher.repoDedupKey(for: $0.githubURL) == key }
    }

    private func saveProject() {
        // Safety net behind the disabled Save button / Enter handler.
        guard duplicateProject == nil else { return }
        let project = ToolProject(
            name: name.trimmingCharacters(in: .whitespaces),
            shortDescription: shortDescription.trimmingCharacters(in: .whitespaces),
            longDescription: longDescription,
            githubURL: urlText.trimmingCharacters(in: .whitespaces),
            websiteURL: websiteURL.trimmingCharacters(in: .whitespaces),
            category: category.trimmingCharacters(in: .whitespaces),
            status: status,
            license: license.trimmingCharacters(in: .whitespaces),
            stars: stars.trimmingCharacters(in: .whitespaces),
            tags: tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            useCases: useCasesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            notes: notes.trimmingCharacters(in: .whitespaces),
            personalNote: personalNote.trimmingCharacters(in: .whitespaces),
            fitScore: fitScore,
            lastUpdatedDate: lastUpdatedDate,
            isLocalFirst: isLocalFirst,
            isSelfHosted: isSelfHosted
        )
        modelContext.insert(project)
        try? modelContext.save()
        CatalogCaptureIntelligenceService.upsertFromCatalogSave(project)
        IconFetcher.fetch(for: project, in: modelContext)
        // Hands-free capture assist: fill use cases/note/tags in the background
        // after the sheet closes, so saving stays instant.
        if captureAssistEnabled, captureAutoGenerate, project.useCases.isEmpty {
            let context = modelContext
            Task { await CaptureAssistService.fillIfNeeded(project, context: context) }
        }
        onSave(project)
        isPresented = false
    }
}
