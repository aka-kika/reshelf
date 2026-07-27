import SwiftUI
import SwiftData

struct InspectView: View {
    let project: ToolProject
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @AppStorage("reshelf.warnOnStrictLicense") private var warnOnStrictLicense = true
    @Query private var appSettingsQuery: [AppSettings]
    @State private var isEditing: Bool = false
    @State private var githubMetadata: RepositoryMetadataRecord?
    @State private var isCloningLocally = false
    @State private var isCloningLocalCopy = false
    @State private var localCopyNotice: String?
    @State private var cloneUpdateStatus: CatalogCloneService.UpdateStatus?
    @State private var isCheckingUpdates = false
    @State private var isPulling = false

    private func loadGitHubMetadata() async {
        let githubURL = project.githubURL
        let projectName = project.name
        let metadata = await Task.detached(priority: .userInitiated) {
            InspectDetailLoader.loadGitHubMetadata(githubURL: githubURL, projectName: projectName)
        }.value
        guard !Task.isCancelled else { return }
        githubMetadata = metadata
    }

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
                    ForEach(inspectorSettings.inspectorSectionOrder) { section in
                        inspectorSectionContent(section)
                    }

                    // Local copy — clone the repo to disk. Always shown now; the
                    // richer v2 clone/fetch section that used to replace it is gone.
                    Divider().padding(.vertical, 12)
                    localCopySection

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

                    // Only shown when it's known: an entry captured before the field
                    // existed, and never cloned, genuinely has no date — and a blank
                    // row reads as "never updated", which would be a lie.
                    if let updated = project.lastUpdatedDate {
                        HStack {
                            Text("Updated")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(updated, format: .dateTime.day().month().year())
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .help("When the project itself last changed upstream — \(updated.formatted(date: .long, time: .shortened))")
                        }
                        .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        Button(action: { presentSheetAfterEndingTextEditing { isEditing = true } }) {
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
        // See presentSheetAfterEndingTextEditing: clear a wedged (claims-presented
        // but not-on-screen) Edit sheet so presentation recovers without a restart.
        .onReceive(NotificationCenter.default.publisher(for: .verifyWedgedSheets)) { _ in
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.isSheet }) else { return }
            isEditing = false
        }
        .task(id: project.id) {
            await loadGitHubMetadata()
        }
        .onChange(of: appRefreshStore.catalogRevision) { _, _ in
            Task { await loadGitHubMetadata() }
        }
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

        case .personalNote:
            // Unlike other sections this renders even when empty — the collapsed
            // row is the only affordance for adding the note from the inspector.
            if inspectorSettings.showInspectorPersonalNote {
                Divider().padding(.vertical, 16)
                PersonalNoteSection(project: project)
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
                        LicenseInfoButton(license: project.license)
                    }
                    if !project.category.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(project.category)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if warnOnStrictLicense, !project.license.isEmpty {
                LicenseCautionBanner(license: project.license)
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

                cloneUpdateRow

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
                Text("Clone a full copy into its category folder (\(CloneLocation.rootURL.lastPathComponent)/\(CatalogCloneService.categoryFolderName(for: project))/<repo>).")
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
        .task(id: project.id) { await autoCheckUpdatesIfCloned() }
    }

    /// Up-to-date / updates-available / check / pull line for a cloned repo.
    @ViewBuilder
    private var cloneUpdateRow: some View {
        if isPulling {
            inlineProgress("Pulling…")
        } else if isCheckingUpdates {
            inlineProgress("Checking for updates…")
        } else {
            switch cloneUpdateStatus {
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            case .updatesAvailable:
                HStack(spacing: 8) {
                    Label("Updates available", systemImage: "arrow.down.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Button("Pull") { pullUpdates() }
                        .controlSize(.small)
                }
            case let .error(message):
                HStack(spacing: 6) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("Check") { Task { await checkUpdates() } }
                        .controlSize(.small)
                }
            case nil:
                Button("Check for updates") { Task { await checkUpdates() } }
                    .controlSize(.small)
            }
        }
    }

    private func inlineProgress(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func checkUpdates() async {
        isCheckingUpdates = true
        let status = await CatalogCloneService.updateStatus(for: project)
        cloneUpdateStatus = status
        isCheckingUpdates = false
        // Keep the list row's "updates available" dot in sync with what we found.
        switch status {
        case .upToDate: broadcastBehind(false)
        case .updatesAvailable: broadcastBehind(true)
        case .error: break
        }
    }

    private func pullUpdates() {
        isPulling = true
        Task {
            do {
                try await CatalogCloneService.pull(project)
                await MainActor.run {
                    isPulling = false
                    cloneUpdateStatus = .upToDate
                    broadcastBehind(false) // clear the orange row dot now that it's current
                }
            } catch {
                await MainActor.run { isPulling = false; cloneUpdateStatus = .error(error.localizedDescription) }
            }
        }
    }

    /// Tell the list whether this repo's clone is behind upstream, so its row dot matches.
    private func broadcastBehind(_ behind: Bool) {
        NotificationCenter.default.post(
            name: .cloneUpdateStatusKnown,
            object: project.id.uuidString,
            userInfo: ["behind": behind]
        )
    }

    private func autoCheckUpdatesIfCloned() async {
        guard CatalogCloneService.isCloned(project),
              cloneUpdateStatus == nil, !isCheckingUpdates else { return }
        await checkUpdates()
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

                // Stars and license already show in the Metadata section up top —
                // this section only carries what the catalog entry doesn't.
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
        return !githubTopicsNotInCatalog(from: githubMetadata).isEmpty
            || hasUniqueDescription
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

 
 
    private static let stackPreviewChipCount = 6

 
 
 
 
 
 
 
    private static let relationshipPreviewCount = 3

 
 
 
    private static let recommendationPreviewCount = 3

 
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

 
    private func deleteProject() {
        modelContext.delete(project)
        try? modelContext.save()
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
    /// Only the GitHub metadata row survives from what this used to gather —
    /// the rest fed the v2 Intelligence surfaces, which are gone.
    static func loadGitHubMetadata(githubURL: String, projectName: String) -> RepositoryMetadataRecord? {
        guard !githubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            try IntelligenceDatabase.shared.initialize()
            guard let repository = CatalogIntelligenceStatusResolver.findRepository(
                githubURL: githubURL, projectName: projectName
            ) else { return nil }
            return try IntelligenceDatabase.shared.fetchMetadata(repositoryID: repository.id)
        } catch {
            return nil
        }
    }
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

/// Collapsed "Why I saved this" note with inline editing. Edits write straight
/// to the model; SwiftData autosave persists them without an explicit save.
private struct PersonalNoteSection: View {
    @Bindable var project: ToolProject
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Why I saved this")
                        .font(.system(size: 11, weight: .medium))
                    if !isExpanded, !project.personalNote.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary.opacity(0.7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                TextEditor(text: $project.personalNote)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 54)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(alignment: .topLeading) {
                        if project.personalNote.isEmpty {
                            Text("The reason you cloned this — future you will thank you.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 12)
                                .padding(.leading, 11)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}
