import SwiftUI

/// Icon-only strip when the NavigationSplitView sidebar is hidden (⌘S).
struct CollapsedSidebarRail: View {
    @Binding var selection: SidebarItem?

    private let items: [SidebarItem] = [
        .allProjects, .topShelf, .collector, .yardSale
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == item
                                      ? Color.accentColor.opacity(0.18)
                                      : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: ShelfLayout.collapsedSidebarRailWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .trailing) { Divider() }
    }
}
