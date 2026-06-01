import SwiftUI

struct QueueInspectorView: View {
    @ObservedObject var viewModel: QueueViewModel

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                Text("Queue Inspector")
                    .font(.system(size: 15, weight: .semibold))
            }

            Group {
            if let job = viewModel.selectedJob {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inspectorHeader(for: job)

                        if job.type == "generate_runbook" {
                            RunbookQueueInspectorDetail(job: job, viewModel: viewModel)
                        } else {
                            GenericQueueInspectorDetail(job: job, viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            } else {
                QueueInspectorPlaceholder()
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func inspectorHeader(for job: QueueJobSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(job.displayRepositoryName)
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                Text(job.displayType)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                QueueInspectorStatusBadge(status: job.status)
            }
            if let completedAt = job.completedAt {
                Text("Updated \(formattedDate(completedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso
    }
}

private struct GenericQueueInspectorDetail: View {
    let job: QueueJobSummary
    @ObservedObject var viewModel: QueueViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if job.status == "running" || job.status == "pending" {
                ProgressView(value: job.progress)
            }

            if let error = job.displayError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                if job.canRetry {
                    Button("Retry") { viewModel.retry(job) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if job.canCancel {
                    Button("Cancel", role: .destructive) { viewModel.cancel(job) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct RunbookQueueInspectorDetail: View {
    let job: QueueJobSummary
    @ObservedObject var viewModel: QueueViewModel
    @EnvironmentObject private var appRefreshStore: AppRefreshStore

    @State private var runbook: RepositoryRunbookRecord?
    @State private var freshness: RunbookFreshnessState = .neverGenerated
    @State private var previewText: String?
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            freshnessRow

            if job.status == "running" || job.status == "pending" {
                ProgressView(value: job.progress)
                Text("Generating runbook in background. Suggested commands only — nothing is executed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let previewText, job.status == "completed" {
                Text("Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(previewText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.04))
                    )
            }

            if let loadError {
                Text(loadError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if let error = job.displayError, !error.isEmpty, job.status == "failed" {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            actionRow
        }
        .task(id: job.id) {
            await loadRunbookContext()
        }
        .onChange(of: appRefreshStore.queueRevision) { _, _ in
            Task { await loadRunbookContext() }
        }
        .onChange(of: appRefreshStore.runbookRevision(for: job.repositoryID)) { _, _ in
            Task { await loadRunbookContext() }
        }
    }

    private var freshnessRow: some View {
        HStack(spacing: 8) {
            Text(freshness.badgeTitle)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(freshnessColor.opacity(0.12))
                )
                .foregroundStyle(freshnessColor)

            if let runbook {
                Text("Generated \(formattedDate(runbook.updatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var freshnessColor: Color {
        switch freshness {
        case .neverGenerated:
            return .secondary
        case .fresh:
            return .green
        case .stale:
            return .orange
        case .generatedWithOlderTemplate:
            return .yellow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if job.canRetry {
                Button("Retry") { viewModel.retry(job) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if runbook != nil, let repositoryID = job.repositoryID {
                Button("Open Runbook") {
                    RunbookDeepLinkNotifier.post(RunbookDeepLinkRequest(repositoryID: repositoryID))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let clonePath = job.clonePath, !clonePath.isEmpty {
                Button("Open Clone Folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: clonePath)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func loadRunbookContext() async {
        guard let repositoryID = job.repositoryID else { return }
        do {
            runbook = try RepositoryRunbookService.fetchLatest(repositoryID: repositoryID)
            freshness = try RepositoryRunbookService.evaluateFreshness(runbook, repositoryID: repositoryID)
            if let markdown = runbook?.markdown {
                previewText = RunbookQueuePreview.plainText(from: markdown)
            } else {
                previewText = nil
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return iso
    }
}

private enum RunbookQueuePreview {
    static func plainText(from markdown: String, maxCharacters: Int = 420) -> String {
        let stripped = markdown
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        if stripped.count <= maxCharacters {
            return stripped
        }
        let index = stripped.index(stripped.startIndex, offsetBy: maxCharacters)
        return String(stripped[..<index]) + "…"
    }
}

private struct QueueInspectorStatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.1))
            )
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case "completed":
            return .green
        case "failed":
            return .red
        case "cancelled":
            return .secondary
        case "running":
            return .blue
        default:
            return .orange
        }
    }
}

private struct QueueInspectorPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("Queue")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Select a job in the queue list to inspect details.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
