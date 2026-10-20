import SwiftUI

/// "What's new": a small sheet shown once, on the first launch after an update, and from
/// Help › What's New in reshelf. Copied from CaptureLab (Kika, 2026-10-17: "lets make it a
/// thing"); it needs only the release notes in the bundle, one Markdown file per version in
/// `release-notes/<version>.md`, copied from docs/release-notes.
enum WhatsNew {
    static let lastSeenKey = "whatsNewLastSeenVersion"

    /// The notes' folder in the bundle, copied from docs/release-notes.
    static let notesFolder = "release-notes"

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    /// True once after an update. A first install only remembers the version: nothing is new yet.
    /// `usedBefore`: reshelf added this sheet in 1.16.0, so someone updating from an older
    /// version has no last-seen version yet; their existing backups tell an update from an install.
    static func shouldShow(defaults: UserDefaults = .standard, usedBefore: Bool = false) -> Bool {
        let current = currentVersion
        guard !current.isEmpty else { return false }
        let last = defaults.string(forKey: lastSeenKey)
        if last == nil, !usedBefore { defaults.set(current, forKey: lastSeenKey); return false }
        return last != current && notes(for: current) != nil
    }

    static func markSeen(defaults: UserDefaults = .standard) { defaults.set(currentVersion, forKey: lastSeenKey) }

    /// The notes' lines worth showing: headings and bullets. The install line on top is left out.
    static func notes(for version: String, bundle: Bundle = .main, folder: String = WhatsNew.notesFolder) -> [Line]? {
        guard let url = bundle.url(forResource: version, withExtension: "md", subdirectory: folder),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = parse(text)
        return lines.isEmpty ? nil : lines
    }

    enum Line: Hashable {
        case heading(String)
        case bullet(AttributedString)
    }

    /// "New in 0.6.1" and "Fixes in 0.6.1 (the review, all 9 items)" become headings, "- **Bold:** text"
    /// bullets keep their bold. Text before the first heading or bullet (the install line) is left out.
    static func parse(_ text: String) -> [Line] {
        var out: [Line] = []
        for raw in text.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") {
                let body = String(t.dropFirst(2))
                let attributed = (try? AttributedString(markdown: body)) ?? AttributedString(body)
                out.append(.bullet(attributed))
            } else if t.hasPrefix("#") || (!t.isEmpty && !t.hasSuffix(".") && !t.contains("](")) {
                let heading = t.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { out.append(.heading(heading)) }
            }
        }
        return out
    }
}

/// The sheet: the app's icon and name, "What's new in <version>", the notes, one Continue button.
struct WhatsNewSheet: View {
    let appName: String
    let lines: [WhatsNew.Line]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Text("What's new in \(appName) \(WhatsNew.currentVersion)").font(.title3.weight(.semibold))
            }
            .padding(.top, 24)
            .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        switch line {
                        case .heading(let text):
                            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                        case .bullet(let text):
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(.tint).frame(width: 5, height: 5).offset(y: -2)
                                Text(text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Continue", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
    }
}
