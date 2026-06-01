import SwiftUI

struct QueueView: View {
    @ObservedObject var viewModel: QueueViewModel

    var body: some View {
        VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                HStack {
                    Text("Queue")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(action: { viewModel.reload() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh queue")
                }
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(16)
            }

            if viewModel.jobs.isEmpty {
                QueueEmptyState()
            } else {
                List(selection: $viewModel.selectedJobID) {
                    ForEach(viewModel.sections, id: \.status) { section in
                        Section(section.title) {
                            ForEach(section.jobs) { job in
                                QueueJobRow(
                                    job: job,
                                    isBusy: viewModel.busyJobIDs.contains(job.id),
                                    onRetry: { viewModel.retry(job) },
                                    onCancel: { viewModel.cancel(job) }
                                )
                                .tag(Optional(job.id))
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct QueueJobRow: View {
    let job: QueueJobSummary
    let isBusy: Bool
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(tintColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(job.displayRepositoryName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(job.displayType)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        QueueStatusBadge(status: job.status)
                    }
                }

                Spacer()

                if job.canRetry {
                    Button("Retry", action: onRetry)
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                        .disabled(isBusy)
                }

                if job.canCancel {
                    Button("Cancel", role: .destructive, action: onCancel)
                        .font(.system(size: 11))
                        .buttonStyle(.borderless)
                        .disabled(isBusy)
                }
            }

            if job.status == "running" || job.status == "pending" {
                ProgressView(value: job.progress)
                    .controlSize(.small)
            }

            if let error = job.displayError, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch job.status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed":
            return "xmark.octagon.fill"
        case "cancelled":
            return "minus.circle.fill"
        case "running":
            return "arrow.triangle.2.circlepath"
        default:
            return "clock"
        }
    }

    private var tintColor: Color {
        switch job.status {
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

private struct QueueStatusBadge: View {
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

private struct QueueEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No jobs yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Captured GitHub repositories will appear here while metadata and clone work runs.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QueueSection {
    var status: String
    var title: String
    var jobs: [QueueJobSummary]
}

@MainActor
final class QueueViewModel: ObservableObject {
    @Published private(set) var jobs: [QueueJobSummary] = []
    @Published private(set) var busyJobIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var selectedJobID: String?

    private let database: IntelligenceDatabase
    private var pollingTask: Task<Void, Never>?

    init(database: IntelligenceDatabase = .shared) {
        self.database = database
    }

    deinit {
        pollingTask?.cancel()
    }

    var selectedJob: QueueJobSummary? {
        guard let selectedJobID else { return nil }
        return jobs.first { $0.id == selectedJobID }
    }

    fileprivate var sections: [QueueSection] {
        [
            section(status: "pending", title: "Pending"),
            section(status: "running", title: "Running"),
            section(status: "failed", title: "Failed"),
            section(status: "cancelled", title: "Cancelled"),
            section(status: "completed", title: "Completed")
        ].filter { !$0.jobs.isEmpty }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        reload()
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                reload()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func reload() {
        do {
            try database.initialize()
            jobs = try database.fetchIngestionJobSummaries()
            if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
                self.selectedJobID = jobs.first?.id
            } else if selectedJobID == nil {
                selectedJobID = jobs.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ job: QueueJobSummary) {
        busyJobIDs.insert(job.id)
        defer { busyJobIDs.remove(job.id) }

        do {
            try database.cancelIngestionJob(id: job.id)
            GitProcessRegistry.shared.terminate(id: job.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retry(_ job: QueueJobSummary) {
        busyJobIDs.insert(job.id)
        Task {
            defer { busyJobIDs.remove(job.id) }

            do {
                try await retryJob(job)
                reload()
            } catch {
                errorMessage = error.localizedDescription
                reload()
            }
        }
    }

    private func retryJob(_ job: QueueJobSummary) async throws {
        switch job.type {
        case "ecosystem_discovery":
            _ = try await EcosystemDiscoveryService.refresh(database: database,
                                                            jobID: job.id)
        case "clone_repo":
            let repository = try requireRepository(for: job)
            _ = try await RepositoryCloneService.cloneOrFetch(repository: repository,
                                                              database: database,
                                                              jobID: job.id)
        case "fetch_github_metadata":
            let repository = try requireRepository(for: job)
            _ = try await RepositoryIngestionService.ingestMetadata(githubURL: repository.githubURL,
                                                                    database: database,
                                                                    jobID: job.id)
        case "static_analysis":
            let repository = try requireRepository(for: job)
            _ = try await RepositoryStaticAnalyzer.analyze(repository: repository,
                                                           database: database,
                                                           jobID: job.id)
        case "ai_analysis":
            let repository = try requireRepository(for: job)
            _ = try await RepositoryAIAnalyzer.analyze(repository: repository,
                                                       database: database,
                                                       jobID: job.id)
        case "relationship_generation":
            let repository = try requireRepository(for: job)
            _ = try await GraphRelationshipService.generateRelationships(repository: repository,
                                                                         database: database,
                                                                         jobID: job.id)
        case "recommendation_generation":
            let repository = try requireRepository(for: job)
            _ = try await RecommendationEngine.generateRecommendations(repository: repository,
                                                                       database: database,
                                                                       jobID: job.id)
        case "generate_runbook":
            guard let repositoryID = job.repositoryID else {
                throw QueueActionError.repositoryMissing
            }
            _ = try await RepositoryRunbookService.generate(repositoryID: repositoryID,
                                                            force: true,
                                                            database: database,
                                                            jobID: job.id)
        default:
            throw QueueActionError.unsupportedJobType(job.type)
        }
    }

    private func requireRepository(for job: QueueJobSummary) throws -> RepositoryRecord {
        guard let repository = try database.fetchRepository(forJobID: job.id) else {
            throw QueueActionError.repositoryMissing
        }
        return repository
    }

    private func section(status: String, title: String) -> QueueSection {
        QueueSection(status: status,
                     title: title,
                     jobs: jobs.filter { $0.status == status })
    }
}

enum QueueActionError: LocalizedError {
    case repositoryMissing
    case unsupportedJobType(String)

    var errorDescription: String? {
        switch self {
        case .repositoryMissing:
            return "The repository for this job no longer exists."
        case let .unsupportedJobType(type):
            return "Retry is not supported for job type \(type)."
        }
    }
}
