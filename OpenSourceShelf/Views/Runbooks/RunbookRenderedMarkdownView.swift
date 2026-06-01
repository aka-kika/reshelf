import SwiftUI

enum RunbookPreviewMode: String, CaseIterable, Identifiable {
    case rendered = "Rendered"
    case raw = "Raw"

    var id: String { rawValue }
}

enum RunbookMarkdownLayout {
    case compact
    case document
}

struct RunbookRenderedMarkdownView: View {
    let markdown: String
    var layout: RunbookMarkdownLayout = .compact
    @State private var previewMode: RunbookPreviewMode = .rendered

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                if previewMode == .rendered {
                    Button("View raw") { previewMode = .raw }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                } else {
                    Button("View rendered") { previewMode = .rendered }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if layout == .document {
                    markdownBody
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        markdownBody
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 180, maxHeight: 320)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var markdownBody: some View {
        if previewMode == .rendered {
            renderedBody
        } else {
            rawBody
        }
    }

    private var renderedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(RunbookMarkdownParser.parse(markdown)) { block in
                blockView(block)
            }
        }
    }

    private var rawBody: some View {
        Text(markdown)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: RunbookMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        case .paragraph(let text):
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if let attributed = try? AttributedString(markdown: item) {
                            Text(attributed)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                        } else {
                            Text(item)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        case .codeBlock(_, let code):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Suggested command")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Copy") {
                        RunbookExportService.copyToPasteboard(code)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
        case .blockquote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.8))
                    .frame(width: 3)
                if let attributed = try? AttributedString(markdown: text) {
                    Text(attributed)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.orange.opacity(0.08))
            )
        case .horizontalRule:
            Divider()
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 15
        case 2: return 13
        default: return 12
        }
    }
}

struct RunbookMarkdownPreview: View {
    let markdown: String

    var body: some View {
        RunbookRenderedMarkdownView(markdown: markdown)
    }
}
