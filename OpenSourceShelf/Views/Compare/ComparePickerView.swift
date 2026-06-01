import SwiftUI

enum ComparisonSessionFilter: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case favorites = "Favorites"

    var id: String { rawValue }
}

struct ComparePickerView: View {
    @Binding var selectedRepositoryIDs: [String]
    let candidates: [CompareFocusCandidate]
    let sessions: [ComparisonSessionRecord]
    @Binding var sessionFilter: ComparisonSessionFilter
    @Binding var searchQuery: String
    let searchResults: [RepositoryRecord]
    let presetCandidates: [ComparisonPresetCandidate]
    let activePreset: ComparisonPreset?
    let maxSelection: Int
    var onSearch: () -> Void
    var onSelectCandidate: (String) -> Void
    var onLoadSession: ([String]) -> Void
    var onToggleFavorite: (ComparisonSessionRecord) -> Void
    var onSelectPreset: (ComparisonPreset) -> Void
    var onClearPreset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compare repositories")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            presetSection

            HStack(spacing: 8) {
                TextField("Search repos…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit(onSearch)
                Button("Search", action: onSearch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)

            if !selectedRepositoryIDs.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selectedRepositoryIDs, id: \.self) { repositoryID in
                        let label = candidates.first(where: { $0.id == repositoryID })?.fullName
                            ?? searchResults.first(where: { $0.id == repositoryID })?.fullName
                            ?? presetCandidates.first(where: { $0.repositoryID == repositoryID })?.fullName
                            ?? repositoryID
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.system(size: 10))
                                .lineLimit(1)
                            Button(action: { remove(repositoryID) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 12)
            }

            if !searchResults.isEmpty {
                pickerSection(title: "Search results") {
                    ForEach(searchResults, id: \.id) { repository in
                        pickerRow(title: repository.fullName, subtitle: "Add to compare", repositoryID: repository.id) {
                            onSelectCandidate(repository.id)
                        }
                    }
                }
            }

            if let activePreset, !presetCandidates.isEmpty {
                pickerSection(title: "\(activePreset.rawValue) candidates") {
                    ForEach(presetCandidates) { candidate in
                        pickerRow(title: candidate.fullName,
                                  subtitle: candidate.reason,
                                  repositoryID: candidate.repositoryID) {
                            onSelectCandidate(candidate.repositoryID)
                        }
                    }
                }
            }

            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Saved comparisons")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: $sessionFilter) {
                            ForEach(ComparisonSessionFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    .padding(.horizontal, 12)

                    ForEach(sessions.prefix(8)) { session in
                        sessionRow(session)
                    }
                }
            }

            pickerSection(title: "Repositories") {
                ForEach(filteredCandidates) { candidate in
                    pickerRow(title: candidate.fullName,
                              subtitle: candidate.relationshipCount > 0 ? "\(candidate.relationshipCount) relationships" : nil,
                              repositoryID: candidate.id) {
                        onSelectCandidate(candidate.id)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Stack-fit presets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if activePreset != nil {
                    Spacer()
                    Button("Clear", action: onClearPreset)
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)

            FlowLayout(spacing: 5) {
                ForEach(ComparisonPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        onSelectPreset(preset)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(activePreset == preset ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func sessionRow(_ session: ComparisonSessionRecord) -> some View {
        let ids = decodeIDs(session.repositoryIDsJSON)
        return HStack(spacing: 6) {
            Button(action: { onToggleFavorite(session) }) {
                Image(systemName: session.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(session.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(session.isFavorite ? "Remove from favorites" : "Add to favorites")

            Button(action: { onLoadSession(ids) }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title ?? ids.joined(separator: " · "))
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Text("\(ids.count) repos")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private var filteredCandidates: [CompareFocusCandidate] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.fullName.localizedCaseInsensitiveContains(query) }
    }

    private func remove(_ repositoryID: String) {
        selectedRepositoryIDs.removeAll { $0 == repositoryID }
    }

    private func pickerSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            content()
        }
    }

    private func pickerRow(title: String, subtitle: String?, repositoryID: String?, action: @escaping () -> Void) -> some View {
        let isSelected = repositoryID.map { selectedRepositoryIDs.contains($0) } ?? false
        let atCapacity = selectedRepositoryIDs.count >= maxSelection && !isSelected
        return Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(atCapacity)
    }

    private func decodeIDs(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}
