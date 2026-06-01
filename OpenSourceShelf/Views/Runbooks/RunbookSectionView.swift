import AppKit
import SwiftUI

struct RunbookSectionView: View {
    let repositoryID: String?
    let clonePath: String?
    let isIntelligenceReady: Bool

    @EnvironmentObject private var appRefreshStore: AppRefreshStore
    @State private var runbook: RepositoryRunbookRecord?
    @State private var freshness: RunbookFreshnessState = .neverGenerated
    @State private var isGenerating = false
    @State private var notice: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Runbook")
                Spacer(minLength: 8)
                freshnessBadge
            }

            if !isIntelligenceReady {
                Text("Clone locally before generating a test runbook.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                actionRow

                if let notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                if let summary = freshness.summaryText, freshness.isStale {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                if let runbook, let summary = runbook.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if runbook == nil, !isGenerating {
                    Text("Generate a local test guide — open in the runbook window to read, copy, or export.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id("runbook-section")
        .task(id: repositoryID) {
            await refreshRunbook()
        }
        .onChange(of: appRefreshStore.runbookRevision(for: repositoryID)) { _, _ in
            Task { await refreshRunbook() }
        }
        .onChange(of: appRefreshStore.queueRevision) { _, _ in
            Task { await refreshRunbook() }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(primaryActionTitle) {
                enqueueGeneration(force: false)
            }
            .font(.system(size: 11))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isGenerating || repositoryID == nil)

            if runbook != nil {
                Button("Open Runbook") {
                    openRunbookWindow()
                }
                .font(.system(size: 11))
                .controlSize(.small)
                .disabled(isGenerating)

                if let clonePath, !clonePath.isEmpty {
                    Button("Clone Folder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: clonePath)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var primaryActionTitle: String {
        if isGenerating { return "Generating…" }
        return runbook == nil ? "Generate Runbook" : "Re-generate"
    }

    private var freshnessBadge: some View {
        Text(freshness.badgeTitle)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.10))
            )
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func openRunbookWindow() {
        guard let repositoryID else { return }
        RunbookWindowPresenter.present(repositoryID: repositoryID)
    }

    private func refreshRunbook() async {
        guard let repositoryID else {
            runbook = nil
            freshness = .neverGenerated
            return
        }
        do {
            runbook = try RepositoryRunbookService.fetchLatest(repositoryID: repositoryID)
            freshness = try RepositoryRunbookService.evaluateFreshness(runbook, repositoryID: repositoryID)
            isGenerating = RunbookGenerationCoordinator.isGenerating(repositoryID: repositoryID)
            if !isGenerating, notice == "Generating…" || notice == "Force regenerating…" {
                notice = runbook == nil ? nil : "Runbook ready — open the runbook window to read it."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enqueueGeneration(force: Bool) {
        guard let repositoryID else { return }
        isGenerating = true
        errorMessage = nil
        notice = force ? "Force regenerating…" : "Generating…"
        do {
            _ = try RepositoryRunbookService.enqueueGeneration(repositoryID: repositoryID, force: force)
        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
            notice = nil
        }
    }
}
