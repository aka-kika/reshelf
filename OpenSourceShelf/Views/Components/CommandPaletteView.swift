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

    @AppStorage("commandPaletteRecentSearches") private var recentSearchesData: Data = Data()
    @State private var escapeMonitor: Any?

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
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    isPresented = false
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
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
        ScrollView {
            LazyVStack(spacing: 0) {
                if isGitHubURL(query) {
                    captureRow
                }

                if query.isEmpty {
                    recentSearchesSection
                }

                let matches = filteredProjects
                if !matches.isEmpty {
                    Section {
                        ForEach(matches) { project in
                            paletteProjectRow(project)
                        }
                    } header: {
                        sectionHeader(query.isEmpty ? "Projects" : "\(matches.count) result\(matches.count == 1 ? "" : "s")")
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
        .background(Color.accentColor.opacity(0.06))
    }

    @ViewBuilder
    private var recentSearchesSection: some View {
        let recents = recentSearches
        if !recents.isEmpty {
            Section {
                ForEach(recents, id: \.self) { term in
                    Button {
                        query = term
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)
                            Text(term)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionHeader("Recent")
            }
        }
    }

    private func paletteProjectRow(_ project: ToolProject) -> some View {
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
        guard !query.isEmpty else { return Array(allProjects.prefix(20)) }
        let term = query.lowercased()
        return allProjects.filter { $0.matchesSearch(term) }
    }

    private func handleSubmit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if isGitHubURL(trimmed) {
            quickCaptureURL = trimmed
            isPresented = false
        } else {
            saveRecentSearch(trimmed)
            searchText = trimmed
            isPresented = false
        }
    }

    private func selectProject(_ project: ToolProject) {
        selectedProjectID = project.id
        isPresented = false
    }

    // MARK: - Recent searches persistence

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    private func saveRecentSearch(_ term: String) {
        var recents = recentSearches
        recents.removeAll { $0.lowercased() == term.lowercased() }
        recents.insert(term, at: 0)
        if recents.count > 8 { recents = Array(recents.prefix(8)) }
        if let data = try? JSONEncoder().encode(recents) {
            recentSearchesData = data
        }
    }
}

private func isGitHubURL(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("https://github.com/") || trimmed.hasPrefix("github.com/")
}
