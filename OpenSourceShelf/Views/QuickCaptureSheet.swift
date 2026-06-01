import SwiftUI
import SwiftData

struct QuickCaptureSheet: View {
    @Binding var isPresented: Bool
    var onSave: (ToolProject) -> Void
    var initialURL: String = ""

    @Environment(\.modelContext) private var modelContext
    @AppStorage(LabsFeatures.storageKey) private var labsFeaturesEnabled = false

    @State private var urlText: String = ""
    @State private var isFetching: Bool = false
    @State private var errorMessage: String?
    @State private var fetchedInfo: GitHubRepoInfo?
    @State private var isGeneratingAI: Bool = false
    @State private var aiSuggestion: String = ""
    @State private var hasGeneratedAISuggestion: Bool = false
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
    @State private var fitScore: Int = 3
    @State private var stars: String = ""
    @State private var license: String = ""
    @State private var isLocalFirst: Bool = false
    @State private var isSelfHosted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 14))
                Text("Quick Capture")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless).font(.system(size: 13))
                if fetchedInfo != nil {
                    Button("Save") { saveProject() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small).font(.system(size: 13))
                        .disabled(name.isEmpty)
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
                                .onSubmit { fetchRepo() }
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

                    if fetchedInfo != nil {
                        Divider()

                        // Auto-filled fields
                        Group {
                            // AI suggestions are a v2 (Labs) capability — hidden in
                            // the catalog-only default so capture stays zero-setup.
                            if labsFeaturesEnabled {
                                aiSuggestionsSection
                            }
                            field("Name") { TextField("", text: $name) }
                            field("Links") {
                                TextField("GitHub URL", text: $urlText)
                                TextField("Website URL", text: $websiteURL)
                            }
                            HStack(spacing: 16) {
                                field("Category") { TextField("e.g. Database, AI", text: $category) }
                                field("Status") {
                                    Picker("", selection: $status) {
                                        ForEach(ProjectStatus.allCases, id: \.self) { s in
                                            Text(s.displayName).tag(s)
                                        }
                                    }.pickerStyle(.menu).labelsHidden().frame(width: 110)
                                }
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
                            field("Metadata") {
                                TextField("Stars", text: $stars)
                                TextField("License", text: $license)
                            }
                            field("Use Cases") {
                                Text("One per line — AI will suggest ideas below.")
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
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 680)
        .onAppear {
            if !initialURL.isEmpty {
                urlText = initialURL
                fetchRepo()
            }
        }
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
        name = info.fullName?.components(separatedBy: "/").last ?? name
        shortDescription = info.description ?? ""
        longDescription = info.description ?? ""
        websiteURL = info.homepage ?? ""
        stars = info.stars.map { formatStars($0) } ?? ""
        license = info.license?.spdxId ?? info.license?.name ?? ""
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

    /// User-facing reason the AI step is disabled, or `nil` when it's ready.
    /// Provider-aware: covers "nothing configured", a not-yet-wired provider, and
    /// (for Ollama) an unreachable local server.
    private var aiUnavailableReason: String? {
        let settings = AppSettings.current(in: modelContext)
        guard !settings.configuredAIProviders.isEmpty else {
            return "No AI provider is set up. Enable one in Settings → AI Providers."
        }
        let provider = AICompletionService.resolvedProvider(settings: settings)
        switch provider {
        case .ollama:
            if ollamaReachable == false {
                return "Ollama isn't running at \(settings.ollamaBaseURL). Start it, or pick another provider in Settings."
            }
            return nil
        case .appleIntelligence:
            return "Apple Intelligence isn't wired to suggestions yet. Pick Ollama or a cloud provider in Settings."
        case .openAI, .anthropic, .gemini, .githubCopilot:
            return nil
        }
    }

    /// Pre-flights the active provider so the AI button reflects offline state
    /// before the user clicks. Only Ollama needs a reachability ping; cloud
    /// providers surface errors on use.
    private func checkAIReachability() {
        let settings = AppSettings.current(in: modelContext)
        guard AICompletionService.resolvedProvider(settings: settings) == .ollama,
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

    private func saveProject() {
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
            fitScore: fitScore,
            isLocalFirst: isLocalFirst,
            isSelfHosted: isSelfHosted
        )
        modelContext.insert(project)
        try? modelContext.save()
        CatalogCaptureIntelligenceService.upsertFromCatalogSave(project)
        IconFetcher.fetch(for: project, in: modelContext)
        onSave(project)
        isPresented = false
    }
}
