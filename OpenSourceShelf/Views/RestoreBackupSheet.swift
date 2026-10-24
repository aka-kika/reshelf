import SwiftUI
import SwiftData

/// Lists the automatic catalog snapshots in `~/reshelf/backups/` and restores a
/// chosen one. Restore always adds the projects the snapshot has and the catalog
/// lost (matched by GitHub URL). "Put back changes" also returns the projects
/// still in the catalog to their backed-up version — the undo for Yard Sale
/// moves, updating imports and duplicate merges. A backup is written first.
struct RestoreBackupSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var snapshots: [SnapshotInfo] = []
    @State private var selected: URL?
    @State private var resultMessage: String?
    @State private var puttingBackChanges = false
    /// What restoring the selected snapshot would do: (missing, changed).
    @State private var preview: (missing: Int, changed: Int)?
    /// True until the first list is read; reading every file happens off main.
    @State private var isLoading = true

    struct SnapshotInfo: Identifiable {
        var id: URL { url }
        let url: URL
        let date: Date?
        let count: Int
        let reason: String?
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

            if isLoading && snapshots.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshots.isEmpty {
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
                                Text("\(snapshot.count) project\(snapshot.count == 1 ? "" : "s")"
                                     + (snapshot.reason.map { " · \($0)" } ?? ""))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .tag(snapshot.url)
                        .contentShape(Rectangle())
                    }
                }
            }

            Divider()

            if !snapshots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Also put back changes to repos I still have", isOn: $puttingBackChanges)
                        .font(.system(size: 12))
                        .toggleStyle(.checkbox)
                    Text(previewText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

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
        .onAppear { load() }
        .onChange(of: selected) { _, _ in
            resultMessage = nil
            updatePreview()
        }
    }

    private var previewText: String {
        guard let preview else { return "Pick a backup." }
        let missing = preview.missing == 0
            ? "Nothing is missing from your catalog."
            : "Adds back \(preview.missing) repo\(preview.missing == 1 ? "" : "s") your catalog no longer has."
        let changed: String
        if preview.changed == 0 {
            changed = "No repo you still have differs from this backup."
        } else if puttingBackChanges {
            changed = preview.changed == 1
                ? "Puts back 1 changed repo as it was (shelf, tags, notes, folder). Repos added since stay."
                : "Puts back \(preview.changed) changed repos as they were (shelf, tags, notes, folder). Repos added since stay."
        } else {
            changed = "\(preview.changed) repo\(preview.changed == 1 ? "" : "s") changed since; turn this on to put them back."
        }
        return missing + " " + changed
    }

    private func updatePreview() {
        guard let selected else { preview = nil; return }
        let url = selected
        // The file read and decode stay off the main thread. Comparing with
        // the catalog happens back here, where the SwiftData context lives.
        Task {
            let decoded = await Task.detached(priority: .userInitiated) { () -> (rows: [CatalogProjectDTO], folders: [CatalogFolderDTO], recorded: Bool) in
                let data = (try? Data(contentsOf: url)) ?? Data()
                let rows = (try? CatalogExportService.decode(data)) ?? []
                let folders = (try? CatalogExportService.decodeFolders(data)) ?? []
                let recorded = (try? CatalogExportService.didRecordFolders(data)) ?? false
                return (rows, folders, recorded)
            }.value
            guard self.selected == url else { return }
            let plan = CatalogImportService.plan(rows: decoded.rows,
                                                 folders: decoded.folders,
                                                 recordedFolders: decoded.recorded,
                                                 sourceURL: url, context: modelContext)
            preview = (plan.additions.count,
                       CatalogImportService.changedMatches(in: plan, context: modelContext).count)
        }
    }

    /// Reads the files in the background (30 snapshots of a big catalog took
    /// a visible pause on open), then fills the list on main.
    private func load(keeping selection: URL? = nil) {
        Task {
            let summaries = await Task.detached(priority: .userInitiated) {
                CatalogBackupService.snapshotSummaries()
            }.value
            snapshots = summaries.map { summary in
                SnapshotInfo(url: summary.url,
                             date: parseDate(from: summary.url.lastPathComponent),
                             count: summary.count,
                             reason: summary.reason)
            }
            isLoading = false
            selected = selection ?? snapshots.first?.url
            updatePreview()
        }
    }

    private func restore() {
        guard let selected else { return }
        let date = displayDate(snapshots.first { $0.url == selected }?.date)
        let result = CatalogBackupService.restore(from: selected, puttingBackChanges: puttingBackChanges,
                                                  into: modelContext, snapshotDate: date)
        if result.saveFailed {
            resultMessage = "Nothing was restored: the catalog couldn't be saved. Check that the disk has free space."
        } else if result.added == 0 && result.updated == 0 {
            resultMessage = "Nothing to restore: your catalog already matches this backup."
        } else {
            var parts: [String] = []
            if result.added > 0 { parts.append("added back \(result.added)") }
            if result.updated > 0 { parts.append("put back \(result.updated)") }
            resultMessage = "Done: " + parts.joined(separator: ", ") + ". The catalog as it was just before is backed up too."
        }
        AppRefreshBus.emit(.catalogStateUpdated)
        // The restore wrote a new "Before restoring…" backup: list it.
        load(keeping: selected)
    }

    // MARK: - Date helpers

    private func parseDate(from filename: String) -> Date? {
        // catalog-yyyy-MM-dd-HHmmss.json, or …-HHmmss-2.json for a second
        // backup written in the same second; a labelled one ends -before.json.
        let stamp = filename
            .replacingOccurrences(of: "catalog-", with: "")
            .replacingOccurrences(of: ".json", with: "")
            .replacingOccurrences(of: CatalogBackupService.labelledSuffix + "$", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(\d{4}-\d{2}-\d{2}-\d{6})-\d+$"#, with: "$1", options: .regularExpression)
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
