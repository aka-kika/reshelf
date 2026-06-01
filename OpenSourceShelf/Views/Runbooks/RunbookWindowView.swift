import AppKit
import SwiftUI

struct RunbookWindowView: View {
    @EnvironmentObject private var runbookWindowState: RunbookWindowState
    @EnvironmentObject private var appRefreshStore: AppRefreshStore

    @State private var runbook: RepositoryRunbookRecord?
    @State private var repository: RepositoryRecord?
    @State private var clonePath: String?
    @State private var freshness: RunbookFreshnessState = .neverGenerated
    @State private var isGenerating = false
    @State private var notice: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let repositoryID = runbookWindowState.repositoryID {
                runbookContent(repositoryID: repositoryID)
            } else {
                emptySelectionView
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptySelectionView: some View {
        VStack(spacing: 10) {
            Text("No Runbook Selected")
                .font(.system(size: 15, weight: .semibold))
            Text("Open a runbook from the catalog inspector or Actions menu.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private func runbookContent(repositoryID: String) -> some View {
        VStack(spacing: 0) {
            headerBar

            if let notice {
                noticeBanner(notice)
            }
            if let errorMessage {
                noticeBanner(errorMessage, isError: true)
            }

            if isGenerating {
                generatingBanner
            }

            if let runbook {
                ScrollView {
                    RunbookRenderedMarkdownView(markdown: runbook.markdown, layout: .document)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isGenerating {
                emptyRunbookView(repositoryID: repositoryID)
            } else {
                Spacer()
            }
        }
        .task(id: repositoryID) {
            await refresh(repositoryID: repositoryID)
        }
        .onChange(of: appRefreshStore.runbookRevision(for: repositoryID)) { _, _ in
            Task { await refresh(repositoryID: repositoryID) }
        }
        .onChange(of: appRefreshStore.queueRevision) { _, _ in
            Task { await refresh(repositoryID: repositoryID) }
        }
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(runbook?.title ?? "Local Test Runbook")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    if let repository {
                        Text(repository.fullName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                freshnessBadge
            }

            if runbook != nil || isGenerating {
                actionToolbar
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var actionToolbar: some View {
        HStack(spacing: 8) {
            if runbook == nil {
                Button("Generate Runbook") {
                    enqueueGeneration(force: false)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || runbookWindowState.repositoryID == nil)
            } else {
                Button("Re-generate") {
                    enqueueGeneration(force: false)
                }
                .controlSize(.small)
                .disabled(isGenerating)

                Button("Copy Markdown") { copyMarkdown() }
                    .controlSize(.small)
                    .disabled(isGenerating)

                Button("Copy Commands") { copyAllSuggestedCommands() }
                    .controlSize(.small)
                    .disabled(isGenerating)

                Button("Export…") { exportMarkdown() }
                    .controlSize(.small)
                    .disabled(isGenerating)

                saveToCloneButton

                if let clonePath, !clonePath.isEmpty {
                    Button("Reveal Clone") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: clonePath)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var saveToCloneButton: some View {
        if let clonePath, !clonePath.isEmpty {
            Button("Save to Clone Folder") {
                saveToCloneFolder(clonePath: clonePath)
            }
            .controlSize(.small)
            .disabled(isGenerating)
            .help("Writes \(RunbookExportService.cloneFolderFilename) beside the local clone.")
        } else {
            Button("Save to Clone Folder") {}
                .controlSize(.small)
                .disabled(true)
                .help("Clone this repository locally first.")
        }
    }

    private func emptyRunbookView(repositoryID: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No runbook yet")
                .font(.system(size: 15, weight: .semibold))
            Text("Generate a local test guide from repository evidence. reshelf never runs these commands for you.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Generate Runbook") {
                enqueueGeneration(force: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isGenerating)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .id(repositoryID)
    }

    private var generatingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Generating runbook…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    private func noticeBanner(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
    }

    private var freshnessBadge: some View {
        Text(freshness.badgeTitle)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor.opacity(0.12)))
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch freshness {
        case .neverGenerated: return .secondary
        case .fresh: return .green
        case .stale: return .orange
        case .generatedWithOlderTemplate: return .yellow
        }
    }

    private func refresh(repositoryID: String) async {
        errorMessage = nil
        do {
            repository = try IntelligenceDatabase.shared.fetchRepository(id: repositoryID)
            clonePath = repository?.localPath
            runbook = try RepositoryRunbookService.fetchLatest(repositoryID: repositoryID)
            freshness = try RepositoryRunbookService.evaluateFreshness(runbook, repositoryID: repositoryID)
            isGenerating = RunbookGenerationCoordinator.isGenerating(repositoryID: repositoryID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enqueueGeneration(force: Bool) {
        guard let repositoryID = runbookWindowState.repositoryID else { return }
        isGenerating = true
        notice = force ? "Force regenerating…" : "Generating…"
        errorMessage = nil
        do {
            _ = try RepositoryRunbookService.enqueueGeneration(repositoryID: repositoryID, force: force)
        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
            notice = nil
        }
    }

    private func copyAllSuggestedCommands() {
        guard let runbook else { return }
        RunbookCommandCopyService.copyAllSuggestedCommands(from: runbook.markdown)
        notice = "Commands copied — review before running."
    }

    private func copyMarkdown() {
        guard let runbook else { return }
        RunbookExportService.copyToPasteboard(runbook.markdown)
        notice = "Copied Markdown to the clipboard."
    }

    private func exportMarkdown() {
        guard let runbook,
              let repository = try? IntelligenceDatabase.shared.fetchRepository(id: runbook.repositoryID) else { return }
        let filename = RunbookExportService.defaultFilename(for: repository, generatedAt: runbook.updatedAt)
        if RunbookExportService.saveMarkdown(runbook.markdown, suggestedFilename: filename) != nil {
            recordExport(for: runbook)
            notice = "Runbook exported."
        }
    }

    private func saveToCloneFolder(clonePath: String) {
        guard let runbook else { return }
        do {
            let url = try RunbookExportService.saveMarkdownToCloneFolder(runbook.markdown, clonePath: clonePath)
            recordExport(for: runbook)
            notice = "Saved to \(url.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordExport(for runbook: RepositoryRunbookRecord) {
        guard let repositoryID = runbookWindowState.repositoryID else { return }
        do {
            try RepositoryRunbookService.recordExport(runbookID: runbook.id)
            AppRefreshBus.emit(.runbookExported(repositoryID: repositoryID, exportedCount: 1))
            Task { await refresh(repositoryID: repositoryID) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
