import SwiftUI
import SwiftData

struct AddProjectSheet: View {
    @Binding var isPresented: Bool
    var onSave: (ToolProject) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var existingProjects: [ToolProject]

    @State private var name: String = ""
    @State private var githubURL: String = ""
    @State private var websiteURL: String = ""
    @State private var category: String = ""
    @State private var shortDescription: String = ""
    @State private var status: ProjectStatus = .collector
    @State private var tagsText: String = ""
    @State private var notes: String = ""
    @State private var fitScore: Int = 3
    @State private var useCasesText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Project")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
                Button("Save") { saveProject() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .disabled(name.isEmpty || duplicateProject != nil)
                    .help(duplicateProject.map { "“\($0.name)” is already in your catalog." } ?? "")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name") {
                        TextField("Project name", text: $name)
                    }
                    field("Links") {
                        TextField("GitHub URL", text: $githubURL)
                        TextField("Website URL", text: $websiteURL)
                    }
                    HStack(spacing: 16) {
                        field("Category") {
                            TextField("e.g. Database, AI, macOS", text: $category)
                        }
                        field("Status") {
                            Picker("", selection: $status) {
                                ForEach(ProjectStatus.allCases, id: \.self) { s in
                                    Label(s.displayName, systemImage: s.sfSymbol).tag(s)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                    field("Description") {
                        TextField("Short description", text: $shortDescription)
                    }
                    field("Use Cases") {
                        Text("Practical ways this tool fits into real workflows. One per line.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 2)
                        TextEditor(text: $useCasesText)
                            .font(.system(size: 12))
                            .frame(height: 72)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                            .overlay(alignment: .topLeading) {
                                if useCasesText.isEmpty {
                                    Text("Build internal admin panels\nPrototype data models\nReplace spreadsheets")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 10)
                                        .padding(.leading, 6)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    field("Tags (comma-separated)") {
                        TextField("database, self-hosted, local-first", text: $tagsText)
                    }
                    field("Notes") {
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .frame(height: 72)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                            .overlay(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("Personal observations, setup tips, integration ideas…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 10)
                                        .padding(.leading, 6)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    field("Personal Fit") {
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= fitScore ? "star.fill" : "star")
                                    .font(.system(size: 14))
                                    .foregroundStyle(i <= fitScore ? .yellow : .secondary.opacity(0.3))
                                    .onTapGesture { fitScore = i }
                            }
                            Text(fitLabel(for: fitScore))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 620)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
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

    /// Existing entry for the same repo (only when a GitHub URL is given), to block dupes.
    private var duplicateProject: ToolProject? {
        let key = IconFetcher.repoDedupKey(for: githubURL)
        guard IconFetcher.extractOwnerRepo(from: githubURL) != nil, !key.isEmpty else { return nil }
        return existingProjects.first { IconFetcher.repoDedupKey(for: $0.githubURL) == key }
    }

    private func saveProject() {
        guard duplicateProject == nil else { return }
        let project = ToolProject(
            name: name.trimmingCharacters(in: .whitespaces),
            shortDescription: shortDescription.trimmingCharacters(in: .whitespaces),
            githubURL: githubURL.trimmingCharacters(in: .whitespaces),
            websiteURL: websiteURL.trimmingCharacters(in: .whitespaces),
            category: category.trimmingCharacters(in: .whitespaces),
            status: status,
            tags: tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            useCases: useCasesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            notes: notes.trimmingCharacters(in: .whitespaces),
            fitScore: fitScore
        )
        modelContext.insert(project)
        try? modelContext.save()
        CatalogCaptureIntelligenceService.upsertFromCatalogSave(project)
        IconFetcher.fetch(for: project, in: modelContext)
        onSave(project)
        isPresented = false
    }
}
