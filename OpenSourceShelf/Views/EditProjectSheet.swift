import SwiftUI

struct EditProjectSheet: View {
    let project: ToolProject
    @Binding var isPresented: Bool

    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var githubURL: String
    @State private var websiteURL: String
    @State private var category: String
    @State private var shortDescription: String
    @State private var longDescription: String
    @State private var status: ProjectStatus
    @State private var tagsText: String
    @State private var useCasesText: String
    @State private var notes: String
    @State private var fitScore: Int
    @State private var stars: String
    @State private var license: String
    @State private var isLocalFirst: Bool
    @State private var isSelfHosted: Bool

    init(project: ToolProject, isPresented: Binding<Bool>) {
        self.project = project
        self._isPresented = isPresented
        self._name = State(initialValue: project.name)
        self._githubURL = State(initialValue: project.githubURL)
        self._websiteURL = State(initialValue: project.websiteURL)
        self._category = State(initialValue: project.category)
        self._shortDescription = State(initialValue: project.shortDescription)
        self._longDescription = State(initialValue: project.longDescription)
        self._status = State(initialValue: project.status)
        self._tagsText = State(initialValue: project.tags.joined(separator: ", "))
        self._useCasesText = State(initialValue: project.useCases.joined(separator: "\n"))
        self._notes = State(initialValue: project.notes)
        self._fitScore = State(initialValue: project.fitScore)
        self._stars = State(initialValue: project.stars)
        self._license = State(initialValue: project.license)
        self._isLocalFirst = State(initialValue: project.isLocalFirst)
        self._isSelfHosted = State(initialValue: project.isSelfHosted)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Project")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
                Button("Save") { saveChanges() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .disabled(name.isEmpty)
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
                            TextField("Category", text: $category)
                        }
                        field("Status") {
                            Picker("", selection: $status) {
                                ForEach(ProjectStatus.allCases, id: \.self) { s in
                                    Text(s.displayName).tag(s)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 110)
                        }
                    }
                    field("Description") {
                        TextField("Short description", text: $shortDescription)
                        TextEditor(text: $longDescription)
                            .frame(height: 60)
                            .overlay(alignment: .topLeading) {
                                if longDescription.isEmpty {
                                    Text("Long description…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    field("Metadata") {
                        TextField("Stars (e.g. 18.2k)", text: $stars)
                        TextField("License (e.g. MIT)", text: $license)
                    }
                    field("Use Cases") {
                        Text("Practical ways this tool fits into real workflows. One per line.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 2)
                        TextEditor(text: $useCasesText)
                            .frame(height: 80)
                            .overlay(alignment: .topLeading) {
                                if useCasesText.isEmpty {
                                    Text("Build internal admin panels\nPrototype data models\nReplace spreadsheets for team workflows")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    field("Tags (comma-separated)") {
                        TextField("database, self-hosted, local-first", text: $tagsText)
                    }
                    field("Notes") {
                        TextEditor(text: $notes)
                            .frame(height: 80)
                            .overlay(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("Personal observations, setup tips, integration ideas…")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
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
                    field("Flags") {
                        Toggle("Local-First", isOn: $isLocalFirst)
                        Toggle("Self-Hosted", isOn: $isSelfHosted)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 720)
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
        .toggleStyle(.checkbox)
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

    private func saveChanges() {
        project.name = name.trimmingCharacters(in: .whitespaces)
        project.githubURL = githubURL.trimmingCharacters(in: .whitespaces)
        project.websiteURL = websiteURL.trimmingCharacters(in: .whitespaces)
        project.category = category.trimmingCharacters(in: .whitespaces)
        project.shortDescription = shortDescription.trimmingCharacters(in: .whitespaces)
        project.longDescription = longDescription
        project.status = status
        project.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        project.useCases = useCasesText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        project.notes = notes.trimmingCharacters(in: .whitespaces)
        project.fitScore = fitScore
        project.stars = stars.trimmingCharacters(in: .whitespaces)
        project.license = license.trimmingCharacters(in: .whitespaces)
        project.isLocalFirst = isLocalFirst
        project.isSelfHosted = isSelfHosted
        try? modelContext.save()
        isPresented = false
    }
}
