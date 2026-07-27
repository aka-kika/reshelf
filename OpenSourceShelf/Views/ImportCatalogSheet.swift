import SwiftUI
import SwiftData

/// Confirms what a catalog JSON file will do before it touches the catalog.
/// The file is already chosen and parsed by the time this appears (the open
/// panel runs first, with no sheet on screen — a modal inside a sheet is the
/// hottest path for the ViewBridge presentation wedge).
struct ImportCatalogSheet: View {
    let request: ImportCatalogRequest
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var plan: CatalogImportService.Plan?
    @State private var updateExisting = false
    @State private var result: CatalogImportService.Result?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.secondary)
                Text("Import Catalog")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { isPresented = false }
                    .buttonStyle(.borderless)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(request.url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let result {
                        resultSummary(result)
                    } else if let plan {
                        planSummary(plan)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                if result == nil {
                    Button("Import") { runImport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.map(\.isEmpty) ?? true)
                }
            }
            .padding(12)
        }
        .frame(width: 460, height: 400)
        .onAppear(perform: buildPlan)
    }

    // MARK: - Sections

    @ViewBuilder
    private func planSummary(_ plan: CatalogImportService.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            row(count: plan.additions.count,
                label: "new project\(plan.additions.count == 1 ? "" : "s") to add",
                symbol: "plus.circle")

            if !plan.matches.isEmpty {
                row(count: plan.matches.count,
                    label: "already in your catalog",
                    symbol: "equal.circle")

                Toggle("Also update the projects I already have", isOn: $updateExisting)
                    .font(.system(size: 12))
                    .toggleStyle(.checkbox)

                Text(updateExisting
                     ? "Their details will be replaced with the file's version. Use this when moving a catalog between Macs."
                     : "They'll be left exactly as they are.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if plan.isEmpty {
                Text("This file has nothing your catalog is missing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("A backup is taken before importing, so you can undo this from Restore from Backup.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func resultSummary(_ result: CatalogImportService.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Import complete")
                    .font(.system(size: 13, weight: .medium))
            }
            row(count: result.added, label: "added", symbol: "plus.circle")
            if result.updated > 0 {
                row(count: result.updated, label: "updated", symbol: "arrow.triangle.2.circlepath")
            }
            if result.skipped > 0 {
                row(count: result.skipped, label: "left unchanged (already in your catalog)", symbol: "equal.circle")
            }
        }
    }

    private func row(count: Int, label: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func buildPlan() {
        plan = CatalogImportService.plan(rows: request.rows,
                                         folders: request.folders,
                                         sourceURL: request.url,
                                         context: modelContext)
    }

    private func runImport() {
        guard let plan else { return }
        result = CatalogImportService.apply(plan,
                                            updatingExisting: updateExisting,
                                            into: modelContext)
    }
}

/// The parsed file, handed to the sheet so it presents with everything it needs.
struct ImportCatalogRequest: Identifiable {
    let id = UUID()
    let url: URL
    let rows: [CatalogProjectDTO]
    /// Folders named in the file; empty for exports written before folders.
    let folders: [CatalogFolderDTO]
}
