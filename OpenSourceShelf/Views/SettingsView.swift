import SwiftUI
import SwiftData
import AppKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings

    // Inspector section ordering
    @State private var sectionOrder: [InspectorSection] = InspectorSection.allCases

    // Appearance (light / dark / system)
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @AppStorage(CaptureAssist.storageKey) private var captureAssistEnabled = true
    @AppStorage(CaptureAssist.autoGenerateKey) private var captureAutoGenerate = true
    @AppStorage(LicenseInfo.warnStorageKey) private var warnOnStrictLicense = true
    @AppStorage(SidebarTagRanking.modeKey) private var sidebarTagsMode: SidebarTagRanking.Mode = .top

    // Capture Assist backfill of entries without use cases
    @State private var isBackfilling = false
    @State private var backfillStatus = ""

    // GitHub token (Keychain-backed; the field is only ever a new value to save)
    @State private var githubTokenText = ""
    @State private var githubTokenStored = false
    @State private var githubTokenStatus = ""
    @State private var isCheckingGitHubToken = false

    // Agent skill install feedback
    @State private var skillInstallStatus = ""
    @State private var isFillingLastUpdated = false
    @State private var lastUpdatedFillStatus = ""

    // Mirrors Sparkle's own preference; the updater stays the source of truth.
    @State private var autoCheckForUpdates = UpdaterService.shared.automaticallyChecksForUpdates
    @ObservedObject private var updater = UpdaterService.shared

    // Repository clone location (empty = default ~/reshelf/repos)
    @AppStorage(CloneLocation.storageKey) private var cloneRootPath: String = ""
    // Set when the folder changed and the old one still holds clones.
    @State private var cloneFolderNotice: String?

    init() {
        self._settings = State(initialValue: AppSettings())
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            captureTab
                .tabItem { Label("Capture", systemImage: "sparkles") }
            libraryTab
                .tabItem { Label("Library", systemImage: "books.vertical") }
            guideTab
                .tabItem { Label("Guide", systemImage: "book") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .onAppear {
            settings = AppSettings.current(in: modelContext)
            sectionOrder = settings.inspectorSectionOrder
            githubTokenStored = GitHubAuth.hasToken
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

    // MARK: - Tabs
    //
    // Layout follows Kika's settings spec: no boxes (the window is the surface),
    // a label on the left with its control on the right, one short line of help,
    // and one hairline between sections.

    /// How reshelf looks and what it warns about.
    private var generalTab: some View {
        SettingsPage {
            SettingsSection("Appearance") {
                SettingsRow("Theme") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow("Sidebar tags", detail: "Which tags the sidebar lists.") {
                    Picker("Sidebar tags", selection: $sidebarTagsMode) {
                        Text("Most used").tag(SidebarTagRanking.Mode.top)
                        Text("Recently added").tag(SidebarTagRanking.Mode.recent)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsDivider()
            SettingsSection("Licenses") {
                SettingsRow("License warnings",
                            detail: "A caution in the inspector for copyleft, missing or unclear licenses.") {
                    Toggle("License warnings", isOn: $warnOnStrictLicense)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    /// Getting a repo onto the shelf, and the on-device model that fills it in.
    private var captureTab: some View {
        SettingsPage {
            SettingsSection("Capture Assist") {
                SettingsRow("Fill details with Apple Intelligence",
                            detail: AppleIntelligenceService.availability.isAvailable
                                ? "On-device. Nothing leaves this Mac."
                                : AppleIntelligenceService.availability.label) {
                    Toggle("Fill details", isOn: $captureAssistEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRow("Fill right after each capture") {
                    Toggle("Fill right after each capture", isOn: $captureAutoGenerate)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!captureAssistEnabled)
                }
                SettingsRow("Repos without use cases",
                            detail: backfillStatus.isEmpty ? "Fill them in now. Your own text is never changed." : backfillStatus) {
                    Button(isBackfilling ? "Filling…" : "Fill") { backfillMissingUseCases() }
                        .disabled(isBackfilling
                                  || !captureAssistEnabled
                                  || !AppleIntelligenceService.availability.isAvailable)
                }
            }
            SettingsDivider()
            SettingsSection("GitHub") {
                SettingsRow("Access token", detail: githubTokenDetail) {
                    if githubTokenStored {
                        HStack(spacing: 8) {
                            Button(isCheckingGitHubToken ? "Testing…" : "Test") { checkGitHubToken() }
                                .disabled(isCheckingGitHubToken)
                            Button("Remove") { removeGitHubToken() }
                        }
                    }
                }
                HStack(spacing: 8) {
                    SecureField(githubTokenStored ? "Paste a new token to replace it"
                                                  : "Paste a personal access token",
                                text: $githubTokenText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveGitHubToken() }
                    Button("Save") { saveGitHubToken() }
                        .disabled(githubTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Link("Create a read-only token on GitHub",
                     destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.system(size: 11))
            }
        }
    }

    private var githubTokenDetail: String {
        if !githubTokenStatus.isEmpty { return githubTokenStatus }
        return githubTokenStored
            ? "Saved in your Keychain."
            : "Optional. Raises GitHub's limit from 60 to 5,000 requests an hour."
    }

    /// Where clones live, the agent skill, and what the inspector shows.
    private var libraryTab: some View {
        SettingsPage {
            SettingsSection("Clones") {
                SettingsRow("Clone folder", detail: "New clones go in a folder per category.") {
                    HStack(spacing: 8) {
                        if CloneLocation.isCustom {
                            Button("Reset") { cloneRootPath = "" }
                                .help("Use the default location (~/reshelf/repos)")
                        }
                        Button("Choose…") { chooseCloneFolder() }
                    }
                }
                Text(CloneLocation.rootURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(CloneLocation.rootURL.path)
                    .onChange(of: cloneRootPath) { oldPath, _ in cloneFolderChanged(from: oldPath) }
                if let cloneFolderNotice {
                    Text(cloneFolderNotice)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsRow("Last updated dates",
                            detail: lastUpdatedFillStatus.isEmpty ? "Read from each clone's last commit. Offline." : lastUpdatedFillStatus) {
                    Button(isFillingLastUpdated ? "Reading…" : "Read from Clones") { fillLastUpdatedFromClones() }
                        .disabled(isFillingLastUpdated)
                }
            }
            SettingsDivider()
            SettingsSection("Agent Skill") {
                SettingsRow("reshelf skill for Claude Code",
                            detail: skillInstallStatus.isEmpty ? "Lets your agent use your shelf. Install again after updates." : skillInstallStatus) {
                    Button("Install…") { installReshelfSkill() }
                }
            }
            SettingsDivider()
            SettingsSection("Inspector", detail: "Show or hide sections. Drag to reorder.") {
                VStack(spacing: 2) {
                    ForEach(sectionOrder) { section in
                        InspectorSectionRow(
                            section: section,
                            isVisible: Binding(
                                get: { settings.isVisible(section) },
                                set: { newValue in
                                    settings.setVisible(section, newValue)
                                    CatalogSave.save(modelContext)
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
                                    CatalogSave.save(modelContext)
                                }
                            }
                            return true
                        }
                    }
                }
            }
        }
    }

    /// What is what, in one screen: shelves, row icons, keys, and the agent skill.
    private var guideTab: some View {
        SettingsPage {
            SettingsSection("Shelves") {
                GuideRow(symbol: ProjectStatus.topShelf.sfSymbol, tint: SidebarItem.topShelf.sidebarTint,
                         title: "Top Shelf", text: "Your keepers. Your agent looks here first.")
                GuideRow(symbol: ProjectStatus.collector.sfSymbol, tint: nil,
                         title: "The Collector", text: "Where every new repo lands.")
                GuideRow(symbol: ProjectStatus.yardSale.sfSymbol, tint: SidebarItem.yardSale.sidebarTint,
                         title: "Yard Sale", text: "On the way out. Agents skip it.")
            }
            SettingsDivider()
            SettingsSection("Icons in the list") {
                GuideRow(symbol: "internaldrive", tint: nil,
                         title: "Cloned", text: "On disk. An orange dot means updates to pull.")
                GuideRow(symbol: "exclamationmark.triangle", tint: nil,
                         title: "No clear license", text: "Study it, but don't copy its code.")
            }
            SettingsDivider()
            SettingsSection("Keys") {
                GuideRow(keys: "⌘N", title: "Quick Capture", text: "Save a repo from its GitHub link.")
                GuideRow(keys: "⌘V", title: "Paste a link", text: "A copied GitHub link opens Quick Capture.")
                GuideRow(keys: "⌘K", title: "Search", text: "Find anything on your shelf.")
                GuideRow(keys: "⌘T ⌘Y", title: "Move", text: "To Top Shelf or Yard Sale. ⌘⇧G: The Collector.")
            }
            SettingsDivider()
            SettingsSection("With your agent") {
                GuideRow(step: 1, title: "Install the skill", text: "Library → Agent Skill → Install.")
                GuideRow(step: 2, title: "Ask about your shelf", text: "“Look at my shelf for a markdown editor.”")
                GuideRow(step: 3, title: "It finds and clones",
                         text: "Top Shelf first, then The Collector. It warns about licenses and clones only after you say yes.")
            }
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
        // A symlink means the user keeps their own copy elsewhere (e.g. a skills
        // collection); replacing it with a folder would silently fork it.
        if (try? fm.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            skillInstallStatus = "~/.claude/skills/reshelf is a link to your own copy; left it alone."
            return
        }
        do {
            try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            }
            try fm.copyItem(at: source, to: destination)
            // reshelf-catalog and reshelf-collector were folded into this skill in
            // 1.12; leaving them installed makes agents pick the old workflow.
            for retired in ["reshelf-catalog", "reshelf-collector"] {
                let old = skillsDir.appendingPathComponent(retired, isDirectory: true)
                if fm.fileExists(atPath: old.path) || (try? fm.destinationOfSymbolicLink(atPath: old.path)) != nil {
                    try? fm.trashItem(at: old, resultingItemURL: nil)
                }
            }
            skillInstallStatus = "Installed to ~/.claude/skills/reshelf"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            skillInstallStatus = "Install failed: \(error.localizedDescription)"
        }
    }

    // MARK: - About tab
    //
    // Same shape as Kika's other apps (mcpock, Vera): icon, name, version, one
    // line of what it does, update controls, "Made by Kika" and three icon-only
    // links, then the copyright.

    private static let aboutLinks: [AboutLink] = [
        AboutLink(name: "akakika.com", icon: "social-globe", url: "https://akakika.com"),
        AboutLink(name: "X (@akakikaaa)", icon: "social-x", url: "https://x.com/akakikaaa"),
        AboutLink(name: "GitHub (aka-kika/reshelf)", icon: "social-github", url: "https://github.com/aka-kika/reshelf"),
    ]

    private var aboutTab: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("reshelf")
                    .font(.system(size: 20, weight: .semibold))
                Text("Version \(appVersionString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text("A local-first shelf for the open-source repos you want to remember.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
                    .padding(.top, 4)
            }

            VStack(spacing: 8) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .onChange(of: autoCheckForUpdates) { _, newValue in
                        UpdaterService.shared.automaticallyChecksForUpdates = newValue
                    }
            }
            .padding(.top, 16)

            VStack(spacing: 10) {
                Text("Made by Kika")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(Self.aboutLinks) { link in
                        AboutLinkButton(link: link)
                    }
                }
            }
            .padding(.top, 30)

            Spacer(minLength: 20)
            Text("© 2026 AKAKIKA.COM · MIT License")
                .font(.system(size: 10))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty || build == version ? version : "\(version) (\(build))"
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

    /// reshelf only sees clones in the current folder and never moves them, so
    /// clones left in the old one would quietly show as not cloned (and Clone
    /// would download them again). Say so, with how many and where.
    private func cloneFolderChanged(from oldPath: String) {
        CatalogCloneService.invalidateCloneIndex()
        AppRefreshBus.emit(.catalogStateUpdated)
        let oldRoot = CloneLocation.rootURL(forStoredPath: oldPath)
        guard oldRoot.standardizedFileURL.path != CloneLocation.rootURL.standardizedFileURL.path else {
            cloneFolderNotice = nil
            return
        }
        let left = CatalogCloneService.scanCloneIndex(root: oldRoot).count
        guard left > 0 else {
            cloneFolderNotice = nil
            return
        }
        let clones = left == 1 ? "1 clone stays" : "\(left) clones stay"
        cloneFolderNotice = "\(clones) in \(oldRoot.path). reshelf doesn't move them and only sees clones in the folder above, so they show as not cloned. Move the category folders over yourself, or switch back."
    }

    /// Saves the entered token to the Keychain and immediately verifies it
    /// against GitHub's /rate_limit endpoint (which doesn't count against quota).
    private func saveGitHubToken() {
        let trimmed = githubTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try GitHubAuth.setToken(trimmed)
        } catch {
            // Keep the typed token in the field so a retry needs no re-paste.
            githubTokenStatus = error.localizedDescription
            return
        }
        githubTokenText = ""
        githubTokenStored = true
        githubTokenStatus = "Saved."
        checkGitHubToken()
    }

    private func removeGitHubToken() {
        do {
            try GitHubAuth.removeToken()
        } catch {
            githubTokenStatus = error.localizedDescription
            return
        }
        githubTokenText = ""
        githubTokenStored = false
        githubTokenStatus = "Removed."
    }

    private func checkGitHubToken() {
        isCheckingGitHubToken = true
        Task {
            let result = await GitHubAuth.checkToken()
            await MainActor.run {
                isCheckingGitHubToken = false
                switch result {
                case let .working(limitPerHour):
                    let formatted = limitPerHour.formatted()
                    githubTokenStatus = "Working — \(formatted) requests/hour."
                case .rejected:
                    githubTokenStatus = "GitHub rejected this token — check it hasn't expired."
                case let .failed(detail):
                    githubTokenStatus = "Couldn't verify: \(detail)"
                }
            }
        }
    }

}

// MARK: - Settings building blocks
//
// Semantic colors only (.primary / .secondary / .tertiary), so both appearances work.

/// A scrolling tab page with the shared margins.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A quiet section title, optional one-line help, then its rows.
private struct SettingsSection<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label (and one short line of help) on the left, the control on the right.
private struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var control: Control

    init(_ label: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
                .controlSize(.regular)
        }
    }
}

/// The one hairline between sections.
private struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.vertical, 18)
    }
}

/// One line of the Guide tab: a symbol, key combo or step number, then a
/// bold term and a short explanation.
private struct GuideRow: View {
    enum Lead { case symbol(String, Color?), keys(String), step(Int) }

    let lead: Lead
    let title: String
    let text: String

    init(symbol: String, tint: Color?, title: String, text: String) {
        lead = .symbol(symbol, tint); self.title = title; self.text = text
    }

    init(keys: String, title: String, text: String) {
        lead = .keys(keys); self.title = title; self.text = text
    }

    init(step: Int, title: String, text: String) {
        lead = .step(step); self.title = title; self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            leadView
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var leadView: some View {
        switch lead {
        case let .symbol(name, tint):
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundStyle(tint ?? .secondary)
        case let .keys(keys):
            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        case let .step(number):
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
    }
}

// MARK: - About links

private struct AboutLink: Identifiable {
    let name: String
    /// File name (no extension) in the bundled SocialIcons folder.
    let icon: String
    let url: String
    var id: String { icon }

    /// The mono mark, as a template image so it takes the label color.
    var image: NSImage? {
        guard let url = Bundle.main.url(forResource: icon, withExtension: "pdf", subdirectory: "SocialIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// One icon-only link: the mark on a quiet rounded square, a touch brighter on
/// hover. The name is the tooltip and the accessibility label.
private struct AboutLinkButton: View {
    let link: AboutLink
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
        } label: {
            Group {
                if let image = link.image {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "link")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 17, height: 17)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 38, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.10 : 0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(link.name)
        .accessibilityLabel(link.name)
    }
}

// MARK: - Inspector Section Row (drag-reorderable)

private struct InspectorSectionRow: View {
    let section: InspectorSection
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Image(systemName: section.icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(section.displayName)
                .font(.system(size: 13))

            Spacer()

            Toggle(section.displayName, isOn: $isVisible)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
