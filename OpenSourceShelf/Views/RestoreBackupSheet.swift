import SwiftUI
import SwiftData

/// Lists the automatic catalog snapshots in `~/reshelf/backups/` and restores a
/// chosen one. Restore is a non-destructive merge — it adds any projects from the
/// snapshot that aren't already in the catalog (matched by GitHub URL), so it's
/// safe to run without losing current work.
struct RestoreBackupSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var snapshots: [SnapshotInfo] = []
    @State private var selected: URL?
    @State private var resultMessage: String?

    struct SnapshotInfo: Identifiable {
        var id: URL { url }
        let url: URL
        let date: Date?
        let count: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                Text("Restore from Backup")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderless)
            }
            .padding(16)

            Divider()

            if snapshots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("No backups yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("Snapshots are written automatically as you change your catalog. They appear here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                List(selection: $selected) {
                    ForEach(snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayDate(snapshot.date))
                                    .font(.system(size: 12))
                                Text("\(snapshot.count) project\(snapshot.count == 1 ? "" : "s")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .tag(snapshot.url)
                        .contentShape(Rectangle())
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                if let resultMessage {
                    Text(resultMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Restore Selected") { restore() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil)
            }
            .padding(12)
        }
        .frame(width: 460, height: 440)
        .onAppear(perform: load)
    }

    private func load() {
        snapshots = CatalogBackupService.snapshotURLs().map { url in
            SnapshotInfo(url: url,
                         date: parseDate(from: url.lastPathComponent),
                         count: CatalogBackupService.projects(in: url).count)
        }
        selected = snapshots.first?.url
    }

    private func restore() {
        guard let selected else { return }
        let inserted = CatalogBackupService.restore(from: selected, into: modelContext)
        resultMessage = inserted == 0
            ? "Nothing new to restore — those projects are already in your catalog."
            : "Restored \(inserted) project\(inserted == 1 ? "" : "s") (duplicates skipped)."
    }

    // MARK: - Date helpers

    private func parseDate(from filename: String) -> Date? {
        // catalog-yyyy-MM-dd-HHmmss.json
        let stamp = filename
            .replacingOccurrences(of: "catalog-", with: "")
            .replacingOccurrences(of: ".json", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: stamp)
    }

    private func displayDate(_ date: Date?) -> String {
        guard let date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
