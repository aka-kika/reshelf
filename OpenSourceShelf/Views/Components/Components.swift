import SwiftUI

struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .foregroundColor(textColor)
    }

    // Blue = keeper (calm), gray = neutral default, amber/yellow = needs review.
    private var backgroundColor: Color {
        switch status {
        case .topShelf: .blue.opacity(0.12)
        case .collector: .gray.opacity(0.14)
        case .yardSale: .yellow.opacity(0.20)
        }
    }

    private var textColor: Color {
        switch status {
        case .topShelf: .blue
        case .collector: .secondary
        case .yardSale: .orange
        }
    }
}

// MARK: - License explainer

/// How permissive vs. restrictive a license is, in plain terms.
enum LicenseStrictness {
    case permissive       // MIT, Apache, BSD, ISC…
    case publicDomain     // CC0, Unlicense
    case weakCopyleft     // MPL, LGPL, EPL — share changes to the covered files
    case strongCopyleft   // GPL, AGPL — your whole project must be open-sourced
    case restricted       // BUSL and friends — source-available, usage restricted
    case unknown

    var label: String {
        switch self {
        case .permissive: "Permissive"
        case .publicDomain: "Public domain"
        case .weakCopyleft: "Weak copyleft"
        case .strongCopyleft: "Strong copyleft"
        case .restricted: "Source-available"
        case .unknown: "Unrecognized"
        }
    }

    var color: Color {
        switch self {
        case .permissive, .publicDomain: .green
        case .weakCopyleft: .yellow
        case .strongCopyleft: .orange
        case .restricted: .red
        case .unknown: .gray
        }
    }

    /// Copyleft and source-available licenses warrant a heads-up before reusing the code.
    var requiresCaution: Bool {
        self == .weakCopyleft || self == .strongCopyleft || self == .restricted
    }
}

/// Plain-language explainer for a software license. Not legal advice — a friendly
/// summary so you know what a repo's license lets you do before you reuse its code.
struct LicenseInfo {
    let name: String
    let strictness: LicenseStrictness
    let summary: String
    let allowed: [String]
    let mustDo: [String]
    let takeaway: String

    /// Best-effort match from a stored license string (SPDX id or name).
    static func lookup(_ raw: String) -> LicenseInfo? {
        let k = raw.lowercased()
        func has(_ s: String) -> Bool { k.contains(s) }
        if has("agpl") { return agpl }
        if has("lgpl") { return lgpl }
        if has("gpl") || has("gnu general public") { return gpl }
        if has("mpl") || has("mozilla public") { return mpl }
        if has("epl") || has("eclipse public") { return epl }
        if has("apache") { return apache }
        if has("bsd") { return bsd }
        if has("isc") { return isc }
        if has("mit") { return mit }
        if has("unlicense") { return publicDomain }
        if has("cc0") || has("creative commons zero") || has("public domain") { return publicDomain }
        if has("busl") || has("business source") { return busl }
        if has("bsl") || has("boost") { return boost }
        if has("zlib") { return zlib }
        return nil
    }

    static let mit = LicenseInfo(
        name: "MIT", strictness: .permissive,
        summary: "Short and very permissive — do almost anything as long as you keep the copyright notice.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use", "Sublicense"],
        mustDo: ["Keep the copyright + license notice"],
        takeaway: "Safe in closed-source and commercial projects. Just keep the notice.")

    static let apache = LicenseInfo(
        name: "Apache-2.0", strictness: .permissive,
        summary: "Permissive like MIT, with an explicit patent grant.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use", "Patent use"],
        mustDo: ["Keep notices + the license", "State significant changes you made"],
        takeaway: "Safe for commercial/closed use; note files you changed. Patent-friendly.")

    static let bsd = LicenseInfo(
        name: "BSD", strictness: .permissive,
        summary: "Permissive. The 3-clause variant also forbids using the authors' names to endorse your product.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use"],
        mustDo: ["Keep the copyright + license notice"],
        takeaway: "Like MIT — fine for closed-source/commercial; keep the notice.")

    static let isc = LicenseInfo(
        name: "ISC", strictness: .permissive,
        summary: "A simplified, MIT-equivalent permissive license.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use"],
        mustDo: ["Keep the copyright + license notice"],
        takeaway: "Treat it like MIT.")

    static let boost = LicenseInfo(
        name: "Boost (BSL-1.0)", strictness: .permissive,
        summary: "Very permissive; no notice required when you distribute only binaries.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use"],
        mustDo: ["Keep the license when distributing source"],
        takeaway: "Very permissive — common in C++. Safe for commercial use.")

    static let zlib = LicenseInfo(
        name: "zlib", strictness: .permissive,
        summary: "Permissive; just don't misrepresent who wrote it.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use"],
        mustDo: ["Don't claim you wrote the original", "Keep the notice in source"],
        takeaway: "Permissive and simple — fine for commercial use.")

    static let publicDomain = LicenseInfo(
        name: "Public domain (CC0 / Unlicense)", strictness: .publicDomain,
        summary: "Effectively no conditions at all — the author waived their rights.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use", "No attribution required"],
        mustDo: ["Nothing"],
        takeaway: "Do whatever you want; attribution isn't even required.")

    static let mpl = LicenseInfo(
        name: "MPL-2.0", strictness: .weakCopyleft,
        summary: "File-level copyleft: changes to MPL-covered files stay open, but you can combine them with proprietary code.",
        allowed: ["Commercial use", "Modify", "Distribute", "Private use", "Combine with closed-source"],
        mustDo: ["Keep MPL-covered files open-source & share their source", "Keep notices"],
        takeaway: "OK inside commercial apps — but edits to the MPL files themselves must be shared.")

    static let lgpl = LicenseInfo(
        name: "LGPL", strictness: .weakCopyleft,
        summary: "Lets proprietary software link the library, but changes to the library must be shared and users must be able to relink it.",
        allowed: ["Commercial use", "Modify", "Distribute", "Link from closed-source"],
        mustDo: ["Share changes to the library", "Allow relinking (dynamic linking)", "Keep notices"],
        takeaway: "Usable in closed apps if you link (not fork) the library and share library changes.")

    static let epl = LicenseInfo(
        name: "EPL-2.0", strictness: .weakCopyleft,
        summary: "File-level copyleft similar to MPL, common in the Java/Eclipse world.",
        allowed: ["Commercial use", "Modify", "Distribute", "Combine with closed-source"],
        mustDo: ["Keep EPL-covered files open & share their source", "Keep notices"],
        takeaway: "OK in commercial apps; changes to the EPL files must be shared.")

    static let gpl = LicenseInfo(
        name: "GPL", strictness: .strongCopyleft,
        summary: "Strong copyleft: if you distribute software that includes GPL code, the whole work must be GPL and source-available.",
        allowed: ["Commercial use", "Modify", "Distribute", "Patent use (GPLv3)"],
        mustDo: ["Open-source your whole project under GPL", "Disclose source", "State changes", "Keep notices"],
        takeaway: "Great to learn from. But shipping a product that includes GPL code means your product must be GPL (open source).")

    static let busl = LicenseInfo(
        name: "BUSL-1.1", strictness: .restricted,
        summary: "Source-available, not open-source: you can read and modify it, but production use is restricted until a per-version change date, when it converts to an open license (often Apache/GPL).",
        allowed: ["View source", "Modify", "Non-production / dev use", "Use freely after the change date"],
        mustDo: ["Avoid restricted production use (often: don't run a competing service)", "Check the repo's LICENSE for the exact grant + change date"],
        takeaway: "Fine to study and self-host non-commercially, but read the terms before shipping anything on it — it's not a normal open-source license.")

    static let agpl = LicenseInfo(
        name: "AGPL-3.0", strictness: .strongCopyleft,
        summary: "GPL plus a network clause — even offering it as a web service to others triggers the share-source requirement.",
        allowed: ["Commercial use", "Modify", "Distribute"],
        mustDo: ["Open-source your whole project under AGPL — including when offered over a network", "Disclose source", "State changes"],
        takeaway: "The strictest common license. Reusing its code in a product or SaaS means releasing your source under AGPL. Perfect to study; be very careful about reuse.")
}

/// Small colored pill showing a license's strictness category.
struct LicenseStrictnessPill: View {
    let strictness: LicenseStrictness
    var body: some View {
        Text(strictness.label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(strictness.color.opacity(0.18)))
            .foregroundStyle(strictness.color)
    }
}

/// The popover card explaining one license.
struct LicenseInfoCard: View {
    let info: LicenseInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(info.name).font(.system(size: 13, weight: .semibold))
                LicenseStrictnessPill(strictness: info.strictness)
            }
            Text(info.summary)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            licenseList("You can", info.allowed, symbol: "checkmark.circle.fill", tint: .green)
            licenseList("You must", info.mustDo, symbol: "exclamationmark.circle.fill", tint: .orange)

            Divider()
            Text(info.takeaway)
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("Plain-language summary, not legal advice.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func licenseList(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(tint)
                        .padding(.top, 1)
                    Text(item).font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// An ⓘ button next to a license that opens the explainer popover. Renders nothing
/// for an unrecognized license.
struct LicenseInfoButton: View {
    let license: String
    @State private var showing = false
    var body: some View {
        if let info = LicenseInfo.lookup(license) {
            Button { showing.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("What does the \(info.name) license allow?")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                LicenseInfoCard(info: info)
            }
        }
    }
}

/// Inspector caution shown (when enabled in Settings) for copyleft licenses, with a
/// "Details" button that opens the full explainer.
struct LicenseCautionBanner: View {
    let license: String
    @State private var showing = false
    var body: some View {
        if let info = LicenseInfo.lookup(license), info.strictness.requiresCaution {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(info.strictness.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.name) — \(info.strictness.label.lowercased()). Be careful reusing this code.")
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(info.takeaway)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Details") { showing.toggle() }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(info.strictness.color)
                        .popover(isPresented: $showing, arrowEdge: .bottom) {
                            LicenseInfoCard(info: info)
                        }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(info.strictness.color.opacity(0.10)))
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let s = subview.sizeThatFits(.unspecified)
                if x + s.width > width, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                x += s.width + spacing
                lineHeight = max(lineHeight, s.height)
            }

            size = CGSize(width: width, height: y + lineHeight)
        }
    }
}
