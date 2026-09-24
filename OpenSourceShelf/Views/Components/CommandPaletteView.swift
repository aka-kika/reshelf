import SwiftUI
import SwiftData
import AppKit

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    @Binding var selectedProjectID: UUID?
    @Binding var quickCaptureURL: String

    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]
    @State private var query: String = ""
    @FocusState private var isSearchFocused: Bool

    /// Keyboard highlight over the actionable rows (capture row first when
    /// shown, then results). `nil` until the user arrows down — so Return
    /// without arrowing keeps its original meaning (apply as list search),
    /// and Return after arrowing opens the highlighted row.
    @State private var highlightedIndex: Int?

    @State private var dismissMonitors: [Any] = []

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            resultsList
        }
        .frame(width: 520, height: 420)
        .onAppear {
            query = ""
            isSearchFocused = true
            dismissMonitors = [
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    switch event.keyCode {
                    case 53: // Escape
                        isPresented = false
                        return nil
                    case 125: // Down arrow — the field keeps focus; we steer the list
                        moveHighlight(1)
                        return nil
                    case 126: // Up arrow
                        moveHighlight(-1)
                        return nil
                    default:
                        return event
                    }
                },
                // Menu-style dismissal: a click anywhere outside the palette's
                // sheet window closes it (the main window is blocked by sheet
                // modality anyway, so the click is swallowed, not re-targeted).
                NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
                ) { event in
                    if event.window?.isSheet != true {
                        isPresented = false
                        return nil
                    }
                    return event
                }
            ].compactMap { $0 }
        }
        .onDisappear {
            dismissMonitors.forEach(NSEvent.removeMonitor)
            dismissMonitors = []
        }
        .onChange(of: query) {
            highlightedIndex = nil
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search projects or paste GitHub link…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit { handleSubmit() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                if isGitHubURL(query) {
                    captureRow
                        .id(Self.captureRowID)
                }

                let matches = filteredProjects
                let offset = isGitHubURL(query) ? 1 : 0
                if !matches.isEmpty {
                    Section {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, project in
                            // Scroll ids must follow the project, not the position:
                            // a position id ("row 0") made the lazy stack keep
                            // showing the previous list's row after typing.
                            paletteProjectRow(project, isHighlighted: highlightedIndex == index + offset)
                                .id(project.id.uuidString)
                        }
                    } header: {
                        sectionHeader(query.isEmpty ? "Recently Added" : "\(matches.count) result\(matches.count == 1 ? "" : "s")")
                    }
                } else if !query.isEmpty && !isGitHubURL(query) {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("No projects match \"\(query)\"")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
        }
        .onChange(of: highlightedIndex) {
            if let index = highlightedIndex, let id = scrollID(forRow: index) {
                proxy.scrollTo(id, anchor: nil)
            }
        }
        }
    }

    private var captureRow: some View {
        Button {
            quickCaptureURL = query.trimmingCharacters(in: .whitespaces)
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Capture this repository")
                        .font(.system(size: 13, weight: .medium))
                    Text(query.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "return")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(highlightedIndex == 0 ? 0.15 : 0.06))
    }

    private func paletteProjectRow(_ project: ToolProject, isHighlighted: Bool = false) -> some View {
        Button {
            selectProject(project)
        } label: {
            HStack(spacing: 10) {
                ProjectIcon(project: project)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !project.shortDescription.isEmpty {
                        Text(project.shortDescription)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if !project.category.isEmpty {
                    Text(project.category)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var filteredProjects: [ToolProject] {
        guard !query.isEmpty else {
            // Empty query → the repos you added most recently (a more useful empty
            // state than the first 20 alphabetically).
            return Array(allProjects.sorted { $0.addedDate > $1.addedDate }.prefix(8))
        }
        let term = query.lowercased()
        return allProjects.filter { $0.matchesSearch(term) }
    }

    private static let captureRowID = "capture-row"

    /// The scroll id of the n-th highlightable row (capture row first, when shown).
    private func scrollID(forRow index: Int) -> String? {
        let hasCaptureRow = isGitHubURL(query)
        if hasCaptureRow && index == 0 { return Self.captureRowID }
        let projects = filteredProjects
        let projectIndex = index - (hasCaptureRow ? 1 : 0)
        return projects.indices.contains(projectIndex) ? projects[projectIndex].id.uuidString : nil
    }

    /// One slot per actionable row: the capture row (when the query is a
    /// GitHub URL) followed by the visible results.
    private var highlightableCount: Int {
        (isGitHubURL(query) ? 1 : 0) + filteredProjects.count
    }

    private func moveHighlight(_ delta: Int) {
        let count = highlightableCount
        guard count > 0 else { return }
        guard let current = highlightedIndex else {
            // First Down enters the list at the top; Up from the field is a no-op.
            if delta > 0 { highlightedIndex = 0 }
            return
        }
        highlightedIndex = min(max(current + delta, 0), count - 1)
    }

    /// Opens the highlighted row. Returns false when nothing is highlighted so
    /// Return can fall through to its original meaning.
    private func activateHighlighted() -> Bool {
        guard let index = highlightedIndex else { return false }
        let hasCaptureRow = isGitHubURL(query)
        if hasCaptureRow && index == 0 {
            quickCaptureURL = query.trimmingCharacters(in: .whitespaces)
            isPresented = false
            return true
        }
        let projects = filteredProjects
        let projectIndex = index - (hasCaptureRow ? 1 : 0)
        guard projects.indices.contains(projectIndex) else { return false }
        selectProject(projects[projectIndex])
        return true
    }

    private func handleSubmit() {
        if activateHighlighted() { return }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if isGitHubURL(trimmed) {
            quickCaptureURL = trimmed
            isPresented = false
        } else {
            searchText = trimmed
            isPresented = false
        }
    }

    private func selectProject(_ project: ToolProject) {
        selectedProjectID = project.id
        isPresented = false
    }
}

private func isGitHubURL(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("https://github.com/") || trimmed.hasPrefix("github.com/")
}
