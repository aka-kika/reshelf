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
    /// Links a stopped run didn't get to, kept for the next time the sheet opens.
    @AppStorage("reshelf.importURLs.leftover") private var leftover: String = ""
    @State private var isImporting = false
    @State private var stopRequested = false
    @State private var counts = BulkURLImport.Counts()
    @State private var total = 0
    /// Why the last run stopped early, in plain words; nil when it ran to the end.
    @State private var stopMessage: String?
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
                        Text(stopRequested
                             ? "Stopping after this repo…"
                             : "Importing \(counts.progress)/\(total)…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if done {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Imported \(counts.imported), skipped \(counts.skipped) duplicate\(counts.skipped == 1 ? "" : "s")\(counts.failed.isEmpty ? "." : ", \(counts.failed.count) failed.")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if let stopMessage {
                            Text(stopMessage)
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !counts.failed.isEmpty {
                            Text("Failed: " + counts.failed.joined(separator: ", "))
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                }

                HStack {
                    Spacer()
                    if isImporting {
                        // Stops after the repo in flight; what was saved stays.
                        Button("Stop") { stopRequested = true }
                            .disabled(stopRequested)
                    } else if done && urls.isEmpty {
                        Button("Done") { isPresented = false }
                            .buttonStyle(.borderedProminent)
                    } else {
                        // After a stop the rest is still in the box: import it
                        // now, or close and come back to it later.
                        if done {
                            Button("Done") { isPresented = false }
                        }
                        Button("Import \(urls.count) URL\(urls.count == 1 ? "" : "s")") { runImport() }
                            .buttonStyle(.borderedProminent)
                            .disabled(urls.isEmpty)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 470)
        .onAppear {
            if text.isEmpty { text = leftover }
        }
    }

    private func runImport() {
        let list = urls
        let existingURLs = Set(existing.map { GitHubRepositoryURL.dedupKey(for: $0.githubURL) })
        isImporting = true
        stopRequested = false
        stopMessage = nil
        done = false
        total = list.count
        counts = BulkURLImport.Counts()

        Task {
            let outcome = await BulkURLImport.run(
                list, existing: existingURLs, into: modelContext,
                shouldStop: { stopRequested },
                onProgress: { counts = $0 }
            )
            counts = outcome.counts
            // What's left goes back in the box (and is remembered), so the
            // next run picks up where this one stopped.
            text = outcome.remaining.joined(separator: "\n")
            leftover = text
            switch outcome.stop {
            case .none:
                stopMessage = outcome.remaining.isEmpty ? nil
                    : "The \(outcome.remaining.count) link\(outcome.remaining.count == 1 ? "" : "s") that failed \(outcome.remaining.count == 1 ? "is" : "are") still in the box."
            case .byUser:
                stopMessage = "Stopped. The \(outcome.remaining.count) link\(outcome.remaining.count == 1 ? "" : "s") not imported yet are still in the box."
            case .rateLimit(let resetText):
                stopMessage = BulkURLImport.rateLimitMessage(at: outcome.stoppedAt ?? 0, of: list.count,
                                                             resetText: resetText, hasToken: GitHubAuth.hasToken)
            }
            isImporting = false
            done = true
        }
    }
}

/// The import loop, apart from the view so it can be tested with a fake fetch.
@MainActor
enum BulkURLImport {
    struct Counts {
        var progress = 0
        var imported = 0
        var skipped = 0
        var failed: [String] = []
    }

    enum Stop: Equatable {
        case none
        case byUser
        /// GitHub said no more requests; every later repo would fail too.
        case rateLimit(resetText: String?)
    }

    struct Outcome {
        var counts: Counts
        var stop: Stop
        /// 0-based position of the link the run stopped at, nil when it finished.
        var stoppedAt: Int?
        /// Links to put back in the box: ones that failed, then any not tried
        /// because the run stopped. A skipped duplicate is not here.
        var remaining: [String]
    }

    /// Imports `list` one repo at a time. Stops before the next repo when
    /// `shouldStop` says so, and at the first rate-limit answer.
    static func run(_ list: [String],
                    existing: Set<String>,
                    into context: ModelContext,
                    fetch: (String) async throws -> GitHubRepoInfo = { try await QuickCaptureService.fetchRepoInfo(githubURL: $0) },
                    pause: UInt64 = 250_000_000,
                    shouldStop: () -> Bool,
                    onProgress: (Counts) -> Void) async -> Outcome {
        var counts = Counts()
        // Links whose fetch failed. They go back in the box: an offline run
        // or a bad token used to wipe the whole pasted list.
        var failedURLs: [String] = []
        // Grows as the run imports: the same URL pasted twice in one list
        // must dedupe against what this run already added, not just
        // against the pre-import catalog.
        var seen = existing
        for (index, url) in list.enumerated() {
            if shouldStop() {
                return Outcome(counts: counts, stop: .byUser, stoppedAt: index,
                               remaining: failedURLs + Array(list[index...]))
            }
            let key = GitHubRepositoryURL.dedupKey(for: url)
            if seen.contains(key) {
                counts.skipped += 1
                counts.progress += 1
                onProgress(counts)
                continue
            }
            do {
                let info = try await fetch(url)
                insert(info, url: url, into: context)
                seen.insert(key)
                counts.imported += 1
            } catch CaptureError.rateLimited(let resetText) {
                return Outcome(counts: counts, stop: .rateLimit(resetText: resetText),
                               stoppedAt: index, remaining: failedURLs + Array(list[index...]))
            } catch {
                counts.failed.append(url.split(separator: "/").suffix(2).joined(separator: "/"))
                failedURLs.append(url)
            }
            counts.progress += 1
            onProgress(counts)
            // Gentle pacing so a long list doesn't trip GitHub's rate limit.
            if pause > 0, index < list.count - 1, !shouldStop() {
                try? await Task.sleep(nanoseconds: pause)
            }
        }
        return Outcome(counts: counts, stop: .none, stoppedAt: nil, remaining: failedURLs)
    }

    /// "GitHub's limit was reached at repo 61 of 200; …", `index` 0-based.
    static func rateLimitMessage(at index: Int, of total: Int, resetText: String?, hasToken: Bool) -> String {
        "GitHub's limit was reached at repo \(index + 1) of \(total); it resets \(resetText ?? "within the hour"). "
            + (hasToken
               ? "Import the rest after that: the links not imported yet are still in the box."
               : "Add a token in Settings → Capture, then import the rest: the links not imported yet are still in the box.")
    }

    private static func insert(_ info: GitHubRepoInfo, url: String, into context: ModelContext) {
        let name = info.fullName?.components(separatedBy: "/").last ?? url
        let project = ToolProject(
            name: name,
            shortDescription: info.description ?? "",
            longDescription: info.description ?? "",
            githubURL: WebLink.normalized(url),
            websiteURL: WebLink.normalized(info.homepage ?? ""),
            category: CategoryClassifier.classify(
                language: info.language,
                topics: info.topics,
                description: info.description,
                name: name
            ),
            status: .collector,
            license: info.licenseText,
            stars: info.stars.map(GitHubRepoInfo.formattedStars) ?? "",
            tags: info.topics ?? [],
            lastUpdatedDate: info.pushedAt.flatMap(GitHubDate.parse),
            isLocalFirst: (info.topics ?? []).contains("local-first"),
            isSelfHosted: (info.topics ?? []).contains("self-hosted")
        )
        context.insert(project)
        CatalogSave.save(context)
        CatalogCaptureIntelligenceService.upsertFromCatalogSave(project, prefetched: info)
        IconFetcher.fetch(for: project, in: context)
    }
}
