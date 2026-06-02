import SwiftUI
import SwiftData
import AppKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings

    // Ollama
    @State private var ollamaModels: [OllamaModel] = []
    @State private var isFetchingModels: Bool = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var urlText: String

    // Inspector section ordering
    @State private var sectionOrder: [InspectorSection] = InspectorSection.allCases

    // Appearance (light / dark / system)
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @AppStorage(LabsFeatures.storageKey) private var labsFeaturesEnabled = false

    // Repository clone location (empty = default ~/reshelf/repos)
    @AppStorage(CloneLocation.storageKey) private var cloneRootPath: String = ""

    enum ConnectionStatus: Equatable {
        case unknown, testing, connected, failed(String)

        var label: String {
            switch self {
            case .unknown: "Not tested"
            case .testing: "Testing…"
            case .connected: "Connected"
            case .failed(let msg): "Failed: \(msg)"
            }
        }

        var color: Color {
            switch self {
            case .unknown: .secondary
            case .testing: .orange
            case .connected: .green
            case .failed: .red
            }
        }
    }

    init() {
        self._settings = State(initialValue: AppSettings())
        self._urlText = State(initialValue: "")
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            // AI providers configure the v2 Intelligence engine — only under Labs.
            if labsFeaturesEnabled {
                aiTab
                    .tabItem { Label("AI", systemImage: "sparkles") }
            }
            inspectorTab
                .tabItem { Label("Inspector", systemImage: "sidebar.right") }
        }
        .onAppear {
            urlText = settings.ollamaBaseURL
            loadSettings()
            sectionOrder = settings.inspectorSectionOrder
            if settings.ollamaEnabled {
                fetchModels()
            }
        }
    }

    /// Shared scroll + padding wrapper so every tab gets consistent chrome.
    private func tabScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
                Spacer(minLength: 40)
            }
            .padding(24)
        }
    }

    // MARK: - General tab

    private var generalTab: some View {
        tabScroll {
                // MARK: - Appearance
                sectionHeader("Appearance")

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Choose how reshelf looks. “System” follows your macOS appearance.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.bottom, 12)

                // MARK: - Labs
                sectionHeader("Labs")

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Intelligence (v2 preview)", isOn: $labsFeaturesEnabled)

                    Text("Off by default. Turns on the v2 Intelligence engine: deep AI analysis, runbooks, Compare, and Ecosystems — and reveals the AI Providers settings. Requires a configured AI provider for the AI steps.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.bottom, 12)

                // MARK: - Repository Storage (where repos are cloned)
                sectionHeader("Repository Storage")

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(CloneLocation.rootURL.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(CloneLocation.rootURL.path)
                        Button("Choose…") { chooseCloneFolder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(.system(size: 11))
                        if CloneLocation.isCustom {
                            Button("Reset") { cloneRootPath = "" }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .font(.system(size: 11))
                                .help("Use the default location (~/reshelf/repos)")
                        }
                    }

                    Text("Where repositories are cloned (right-click a repo → Clone Repository, or use the inspector). Repos are organized by owner/name inside this folder. Changing it only affects new clones — existing clones stay where they are.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.bottom, 12)
        }
    }

    // MARK: - AI tab

    private var aiTab: some View {
        tabScroll {
                // MARK: - AI Providers
                sectionHeader("AI Providers")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Use for AI suggestions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("Preferred provider", selection: preferredProviderBinding) {
                        ForEach(AIProviderKind.selectableProviders) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)

                    Text("Quick Capture, runbook polish, and other on-demand suggestions use this provider when it is enabled and configured. Falls back to another ready provider if needed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.bottom, 12)

                // Ollama
                AIProviderSettingsCard(
                    systemImage: AIProviderKind.ollama.systemImage,
                    title: AIProviderKind.ollama.displayName,
                    subtitle: AIProviderKind.ollama.subtitle,
                    isEnabled: $settings.ollamaEnabled
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        // URL field
                        HStack(spacing: 8) {
                            Text("URL")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .leading)
                            TextField("http://localhost:11434", text: $urlText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit { saveURL() }
                            Button("Test") { testConnection() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .font(.system(size: 11))
                        }

                        // Connection status
                        if connectionStatus != .unknown {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(connectionStatus.color)
                                    .frame(width: 6, height: 6)
                                Text(connectionStatus.label)
                                    .font(.system(size: 11))
                                    .foregroundStyle(connectionStatus.color)
                            }
                        }

                        // Models dropdown
                        if !ollamaModels.isEmpty {
                            Divider()
                            HStack(spacing: 8) {
                                Text("Model")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $settings.ollamaSelectedModel) {
                                    Text("None selected").tag("")
                                    ForEach(ollamaModels) { model in
                                        Text(model.name).tag(model.name)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: 220)
                                .onChange(of: settings.ollamaSelectedModel) { _, _ in
                                    persistSettings()
                                }

                                if !settings.ollamaSelectedModel.isEmpty {
                                    if let selected = ollamaModels.first(where: { $0.name == settings.ollamaSelectedModel }) {
                                        Text(selected.sizeFormatted)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if isFetchingModels {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                                Text("Fetching models…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } else if connectionStatus == .connected && ollamaModels.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "cube.box")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text("No models installed. Pull one via Ollama first.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .onChange(of: settings.ollamaEnabled) { _, _ in persistSettings() }

                // Apple Intelligence
                AIProviderSettingsCard(
                    systemImage: AIProviderKind.appleIntelligence.systemImage,
                    title: AIProviderKind.appleIntelligence.displayName,
                    subtitle: AIProviderKind.appleIntelligence.subtitle,
                    isEnabled: $settings.appleIntelligenceEnabled
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                            Text("Available on macOS 15.2+")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Text("Apple Intelligence runs language and diffusion models entirely on-device. No API keys or internet required. Models include writing tools, image generation, and summarization APIs.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                }
                .onChange(of: settings.appleIntelligenceEnabled) { _, _ in persistSettings() }

                CloudAIProviderSettingsCard(provider: .openAI, settings: settings, onSave: persistSettings)
                CloudAIProviderSettingsCard(provider: .anthropic, settings: settings, onSave: persistSettings)
                CloudAIProviderSettingsCard(provider: .gemini, settings: settings, onSave: persistSettings)
                CloudAIProviderSettingsCard(provider: .githubCopilot, settings: settings, onSave: persistSettings)

                sectionHeader("Intelligence")

                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Automatically generate runbook after intelligence completes",
                           isOn: $settings.autoGenerateRunbookAfterIntelligence)
                        .font(.system(size: 12))
                        .onChange(of: settings.autoGenerateRunbookAfterIntelligence) { _, value in
                            RunbookAutoEnqueueSettings.syncFromSettings(value)
                            try? modelContext.save()
                        }

                    Text("When enabled, reshelf queues runbook generation after analysis and recommendations finish. Commands remain suggested only — nothing runs automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.bottom, 12)
        }
    }

    // MARK: - Inspector tab

    private var inspectorTab: some View {
        tabScroll {
                sectionHeader("Inspector")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose which sections appear in the inspector, and drag to reorder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(sectionOrder.filter { labsFeaturesEnabled || !$0.isIntelligence }) { section in
                        InspectorSectionRow(
                            section: section,
                            isVisible: Binding(
                                get: { settings.isVisible(section) },
                                set: { newValue in
                                    settings.setVisible(section, newValue)
                                    try? modelContext.save()
                                }
                            )
                        )
                        .draggable(section.rawValue) {
                            InspectorSectionRow(
                                section: section,
                                isVisible: .constant(settings.isVisible(section))
                            )
                            .frame(width: 280)
                            .opacity(0.8)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let droppedRaw = items.first,
                                  let droppedSection = InspectorSection(rawValue: droppedRaw),
                                  droppedSection != section else { return false }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if let fromIndex = sectionOrder.firstIndex(of: droppedSection),
                                   let toIndex = sectionOrder.firstIndex(of: section) {
                                    sectionOrder.move(fromOffsets: IndexSet(integer: fromIndex),
                                                      toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                    settings.inspectorSectionOrder = sectionOrder
                                    try? modelContext.save()
                                }
                            }
                            return true
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .padding(.bottom, 12)
        }
    }

    // MARK: - Bindings

    private var preferredProviderBinding: Binding<AIProviderKind> {
        Binding(
            get: { settings.preferredAIProvider },
            set: { newValue in
                settings.preferredAIProvider = newValue
                persistSettings()
            }
        )
    }

    // MARK: - Section chrome

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 8)
    }

    // MARK: - Actions

    /// Present a native folder picker and store the chosen path. The user selects
    /// the folder themselves in the panel; we only persist their choice.
    private func chooseCloneFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder where repositories will be cloned"
        panel.directoryURL = CloneLocation.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            cloneRootPath = url.path
        }
    }

    private func loadSettings() {
        self.settings = AppSettings.current(in: modelContext)
        self.urlText = settings.ollamaBaseURL
        AISettingsSnapshot.sync(from: settings)
        RunbookAutoEnqueueSettings.syncFromSettings(settings.autoGenerateRunbookAfterIntelligence)
    }

    private func persistSettings() {
        AISettingsSnapshot.sync(from: settings)
        try? modelContext.save()
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        settings.ollamaBaseURL = trimmed
        persistSettings()
        connectionStatus = .unknown
        ollamaModels = []
    }

    private func testConnection() {
        saveURL()
        let url = settings.ollamaBaseURL
        connectionStatus = .testing
        Task {
            let ok = await OllamaService.testConnection(baseURL: url)
            await MainActor.run {
                connectionStatus = ok ? .connected : .failed("Could not reach Ollama at \(url)")
                if ok { fetchModels() }
            }
        }
    }

    private func fetchModels() {
        let url = settings.ollamaBaseURL
        isFetchingModels = true
        Task {
            do {
                let models = try await OllamaService.fetchModels(baseURL: url)
                await MainActor.run {
                    ollamaModels = models
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    isFetchingModels = false
                }
            }
        }
    }
}

// MARK: - Inspector Section Row (drag-reorderable)

private struct InspectorSectionRow: View {
    let section: InspectorSection
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Image(systemName: section.icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(section.displayName)
                .font(.system(size: 12))

            Spacer()

            Toggle("", isOn: $isVisible)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.02))
        )
        .contentShape(Rectangle())
    }
}
