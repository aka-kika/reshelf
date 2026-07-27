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
    // The v2 Intelligence preview is retired — its switch is gone from Settings
    // and nothing can turn it back on. Kept only until the surfaces it gates
    // are deleted outright (branch: claude/remove-labs).
    private let labsFeaturesEnabled = false
    @AppStorage(CaptureAssist.storageKey) private var captureAssistEnabled = true
    @AppStorage(CaptureAssist.autoGenerateKey) private var captureAutoGenerate = true
    @AppStorage("reshelf.warnOnStrictLicense") private var warnOnStrictLicense = true

    // Capture Assist backfill of entries without use cases
    @State private var isBackfilling = false
    @State private var backfillStatus = ""

    // Agent skill install feedback
    @State private var skillInstallStatus = ""
    @State private var isFillingLastUpdated = false
    @State private var lastUpdatedFillStatus = ""

    // About tab icon hover
    @State private var aboutIconHovering = false

    // Mirrors Sparkle's own preference; the updater stays the source of truth.
    @State private var autoCheckForUpdates = UpdaterService.shared.automaticallyChecksForUpdates

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
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
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

    /// Reads each cloned repo's last commit date off disk. Fill-only: entries
    /// that already have a date (from GitHub, which is more authoritative than a
    /// possibly-stale local checkout) are left alone.
    private func fillLastUpdatedFromClones() {
        isFillingLastUpdated = true
        lastUpdatedFillStatus = ""
        Task { @MainActor in
            let result = await LastUpdatedBackfillService.backfillFromClones(in: modelContext)
            isFillingLastUpdated = false
            if result.filled == 0 && result.skippedNotCloned == 0 && result.failed == 0 {
                lastUpdatedFillStatus = "Every entry already has a date."
            } else {
                var parts = ["Filled \(result.filled)"]
                if result.skippedNotCloned > 0 { parts.append("\(result.skippedNotCloned) not cloned") }
                if result.failed > 0 { parts.append("\(result.failed) unreadable") }
                lastUpdatedFillStatus = parts.joined(separator: " · ")
            }
        }
    }

    /// Fills use cases (plus empty notes/tags) for every entry that has none,
    /// one at a time on the on-device model. Fill-only, hand-edited data is safe.
    private func backfillMissingUseCases() {
        let candidates = CaptureAssistService.projectsMissingUseCases(in: modelContext)
        guard !candidates.isEmpty else {
            backfillStatus = "All entries already have use cases."
            return
        }
        isBackfilling = true
        backfillStatus = "0 of \(candidates.count)…"
        Task {
            var filled = 0
            for (index, project) in candidates.enumerated() {
                if await CaptureAssistService.fillIfNeeded(project, context: modelContext) {
                    filled += 1
                }
                backfillStatus = "\(index + 1) of \(candidates.count)…"
            }
            isBackfilling = false
            backfillStatus = "Done — filled \(filled) of \(candidates.count) entries."
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

                // MARK: - Licenses
                sectionHeader("Licenses")

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Warn about strict (copyleft) licenses", isOn: $warnOnStrictLicense)

                    Text("Shows a caution in the inspector when a repo uses a copyleft license (GPL, AGPL, MPL, LGPL…) that can require you to open-source your own project if you reuse its code. The ⓘ next to any license always explains what it allows — this just surfaces the caution automatically.")
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

                // MARK: - Capture Assist (the one AI feature in the main app)
                sectionHeader("Capture Assist")

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Fill use cases, note, and tags with Apple Intelligence", isOn: $captureAssistEnabled)

                    HStack(spacing: 6) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(AppleIntelligenceService.availability.label)
                            .font(.system(size: 11))
                            .foregroundStyle(AppleIntelligenceService.availability.isAvailable ? .green : .secondary)
                    }

                    Text("Runs entirely on-device — nothing leaves this Mac and no setup is needed.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Toggle("Generate automatically on every capture", isOn: $captureAutoGenerate)
                        .disabled(!captureAssistEnabled)

                    Text("Fills in the background right after you save a capture — no need to open More Details and press Generate.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack(spacing: 10) {
                        Button(isBackfilling ? "Filling…" : "Fill Missing Entries") {
                            backfillMissingUseCases()
                        }
                        .disabled(isBackfilling
                                  || !captureAssistEnabled
                                  || !AppleIntelligenceService.availability.isAvailable)

                        if !backfillStatus.isEmpty {
                            Text(backfillStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Generates use cases for shelved entries that don't have any yet. Entries you already filled in are never touched.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    HStack(spacing: 10) {
                        Button(isFillingLastUpdated ? "Reading clones…" : "Fill “Last Updated” from Clones") {
                            fillLastUpdatedFromClones()
                        }
                        .disabled(isFillingLastUpdated)

                        if !lastUpdatedFillStatus.isEmpty {
                            Text(lastUpdatedFillStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Reads each cloned repo's last commit date off disk so you can sort by Recently Updated. Offline and instant — no GitHub calls, no rate limit. Repos you haven't cloned fill in the next time their details are fetched.")
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

                // MARK: - Agent Skill
                sectionHeader("Agent Skill")

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button("Install reshelf Skill…") {
                            installReshelfSkill()
                        }

                        if !skillInstallStatus.isEmpty {
                            Text(skillInstallStatus)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Installs the reshelf skill for Claude Code at ~/.claude/skills/reshelf, so your agent can browse the shelf — cloned repos, categories, catalog — as a curated code reference. Reinstalling replaces the previous copy (the old one goes to the Trash).")
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

    /// Copies the bundled reshelf skill folder to ~/.claude/skills/reshelf.
    /// An existing install is moved to the Trash (recoverable) before the copy.
    private func installReshelfSkill() {
        guard let source = Bundle.main.url(forResource: "reshelf-skill", withExtension: nil) else {
            skillInstallStatus = "Skill files are missing from this build."
            return
        }
        let fm = FileManager.default
        let skillsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
        let destination = skillsDir.appendingPathComponent("reshelf", isDirectory: true)
        do {
            try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            try fm.copyItem(at: source, to: destination)
            skillInstallStatus = "Installed to ~/.claude/skills/reshelf"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            skillInstallStatus = "Install failed: \(error.localizedDescription)"
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
                        let availability = AppleIntelligenceService.availability
                        HStack(spacing: 6) {
                            Image(systemName: availability.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(availability.isAvailable ? Color.green : Color.orange)
                            Text(availability.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Text("Uses the on-device Apple Foundation model for Quick Capture suggestions and repository intelligence. No API keys or internet required — nothing leaves this Mac.")
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

    // MARK: - About tab

    private var aboutTab: some View {
        tabScroll {
            VStack(spacing: 0) {
                // Icon on a soft glow, with a gentle spring on hover.
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.accentColor.opacity(0.20), .clear],
                                             center: .center, startRadius: 10, endRadius: 85))
                        .frame(width: 168, height: 168)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 108, height: 108)
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                        .scaleEffect(aboutIconHovering ? 1.05 : 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: aboutIconHovering)
                        .onHover { aboutIconHovering = $0 }
                }

                Text("reshelf")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .padding(.top, 2)

                Text("Version \(appVersionString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.top, 10)
                    .onChange(of: autoCheckForUpdates) { _, newValue in
                        UpdaterService.shared.automaticallyChecksForUpdates = newValue
                    }

                if let checked = UpdaterService.shared.lastUpdateCheckDate {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text("A local-first shelf for the open-source tools you want to remember.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 40)

                HStack(spacing: 10) {
                    aboutLink("akakika.com", systemImage: "globe",
                              url: "https://akakika.com")
                    aboutLink("GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                              url: "https://github.com/aka-kika/reshelf")
                    aboutLink("Follow on X", glyph: "𝕏",
                              url: "https://x.com/akakikaaa")
                }
                .padding(.top, 16)

                Text("by KIKA — for people who think in systems")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)

                Text("MIT License · © reshelf contributors")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Capsule link button for the About tab; `glyph` renders a text symbol
    /// (e.g. 𝕏) where no SF Symbol exists.
    private func aboutLink(_ title: String,
                           systemImage: String? = nil,
                           glyph: String? = nil,
                           url: String) -> some View {
        Button {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                }
                if let glyph {
                    Text(glyph).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty || build == version ? version : "\(version) (\(build))"
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
