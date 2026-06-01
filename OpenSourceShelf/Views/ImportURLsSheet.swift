import SwiftUI
import SwiftData

/// Bulk-import: paste GitHub repo URLs (one per line); each is fetched from GitHub
/// and added to the catalog with auto-classified category. Duplicates are skipped.
/// Also the restore path after a data-loss event — paste a recovered URL list.
struct ImportURLsSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var existing: [ToolProject]

    @State private var text: String = ""
    @State private var isImporting = false
    @State private var progress = 0
    @State private var total = 0
    @State private var imported = 0
    @State private var skipped = 0
    @State private var failed: [String] = []
    @State private var done = false

    private var urls: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.secondary)
                Text("Import GitHub URLs")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.borderless)
                    .disabled(isImporting)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Paste GitHub repo URLs, one per line. Each is fetched from GitHub and added to your catalog (name, description, stars, license, tags, auto-category). Duplicates are skipped.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                    .disabled(isImporting)

                if isImporting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Importing \(progress)/\(total)…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if done {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Imported \(imported), skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")\(failed.isEmpty ? "." : ", \(failed.count) failed.")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if !failed.isEmpty {
                            Text("Failed: " + failed.joined(separator: ", "))
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                }

                HStack {
                    Spacer()
                    if done {
                        Button("Done") { isPresented = false }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Import \(urls.count) URL\(urls.count == 1 ? "" : "s")") { runImport() }
                            .buttonStyle(.borderedProminent)
                            .disabled(urls.isEmpty || isImporting)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 470)
    }

    private func runImport() {
        let list = urls
        let existingURLs = Set(existing.map { normalize($0.githubURL) })
        isImporting = true
        done = false
        total = list.count
        progress = 0; imported = 0; skipped = 0; failed = []

        Task {
            for url in list {
                if existingURLs.contains(normalize(url)) {
                    await MainActor.run { skipped += 1; progress += 1 }
                    continue
                }
                do {
                    let info = try await QuickCaptureService.fetchRepoInfo(githubURL: url)
                    await MainActor.run {
                        let name = info.fullName?.components(separatedBy: "/").last ?? url
                        let project = ToolProject(
                            name: name,
                            shortDescription: info.description ?? "",
                            longDescription: info.description ?? "",
                            githubURL: url,
                            websiteURL: info.homepage ?? "",
                            category: CategoryClassifier.classify(
                                language: info.language,
                                topics: info.topics,
                                description: info.description,
                                name: name
                            ),
                            status: .collector,
                            license: info.license?.spdxId ?? info.license?.name ?? "",
                            stars: info.stars.map(formatStars) ?? "",
                            tags: info.topics ?? []
                        )
                        modelContext.insert(project)
                        try? modelContext.save()
                        CatalogCaptureIntelligenceService.upsertFromCatalogSave(project)
                        IconFetcher.fetch(for: project, in: modelContext)
                        imported += 1
                        progress += 1
                    }
                } catch {
                    await MainActor.run {
                        failed.append(url.split(separator: "/").suffix(2).joined(separator: "/"))
                        progress += 1
                    }
                }
                // Gentle pacing so a long list doesn't trip GitHub's rate limit.
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            await MainActor.run { isImporting = false; done = true }
        }
    }

    private func formatStars(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000.0) : "\(count)"
    }

    private func normalize(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
