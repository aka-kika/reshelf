import SwiftUI

enum ShelfLayout {
    /// Shared height for middle + detail column headers so dividers align across the split view.
    /// This row doubles as the window's title bar (the system toolbar band is removed),
    /// so it must be tall enough to comfortably clear the traffic-light controls.
    static let splitColumnHeaderHeight: CGFloat = 38
    static let splitColumnHeaderHorizontalPadding: CGFloat = 16

    static let sidebarWidth = (min: 200.0, ideal: 220.0, max: 320.0)
    static let collapsedSidebarRailWidth: CGFloat = 52
    static let catalogListWidth = (min: 280.0, ideal: 360.0, max: 560.0)
    static let discoveryListWidth = (min: 360.0, ideal: 480.0, max: 680.0)
    static let inspectorWidth = (min: 280.0, ideal: 320.0, max: 420.0)
    static let panelWidth: CGFloat = 260
}

/// Minimal icon button used in the merged title-bar/header row.
/// Mirrors the quiet look of toolbar chrome (secondary glyph, subtle hover).
struct HeaderChromeButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

struct AlignedSplitColumnHeader<Content: View>: View {
    /// Extra leading inset (used by the sidebar column to clear the traffic lights).
    var leadingInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: ShelfLayout.splitColumnHeaderHeight)
                .padding(.leading, ShelfLayout.splitColumnHeaderHorizontalPadding + leadingInset)
                .padding(.trailing, ShelfLayout.splitColumnHeaderHorizontalPadding)

            // The fine hairline under the header row — aligned across all three
            // columns by the sidebar's measured top nudge + content margins.
            Divider()
        }
    }
}
