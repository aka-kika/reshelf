import SwiftUI
import SwiftData

private struct SidebarFilterCounts {
    private var counts: [SidebarItem: Int] = [:]

    init(projects: [ToolProject]) {
        var map: [SidebarItem: Int] = [:]
        for item in SidebarItem.sidebarCatalogItems {
            map[item] = projects.filter { item.matchesCatalogFilter($0) }.count
        }
        counts = map
    }

    func count(for item: SidebarItem) -> Int {
        counts[item, default: 0]
    }
}

struct SidebarView: View {
    @Binding var selection: ShelfSelection?
    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]

    /// Computed (not cached) so counts refresh on any catalog change — including a
    /// project moving between shelves, which changes status but not the count.
    private var filterCounts: SidebarFilterCounts {
        SidebarFilterCounts(projects: allProjects)
    }

    var body: some View {
        // Build the counts once per render (the struct rebuilds on each access).
        let counts = filterCounts
        let categories = SidebarItem.sidebarCategoryItems.filter {
            counts.count(for: $0) > 0 || selection == .builtin($0)
        }
        return VStack(spacing: 0) {
            // Leading inset clears the traffic lights, which share this row now
            // that the header is the title bar.
            AlignedSplitColumnHeader(leadingInset: ShelfLayout.trafficLightHeaderInset) {
                ReshelfBrandHeader()
            }

            List(selection: $selection) {
                Section(SidebarSection.library.rawValue) {
                    SidebarRow(item: .allProjects, count: counts.count(for: .allProjects))
                    SidebarRow(item: .topShelf, count: counts.count(for: .topShelf))
                    SidebarRow(item: .collector, count: counts.count(for: .collector))
                    SidebarRow(item: .yardSale, count: counts.count(for: .yardSale))
                    SidebarRow(item: .cloned, count: counts.count(for: .cloned))
                }

                if !categories.isEmpty {
                    Section(SidebarSection.categories.rawValue) {
                        ForEach(categories) { item in
                            SidebarRow(item: item, count: counts.count(for: item))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .listSectionSeparator(.hidden, edges: .top)
            .scrollContentBackground(.hidden)
            // Top breathing room tuned so the first sidebar row aligns with the
            // first row of the main list (measured 3pt higher otherwise) while the
            // header divider stays aligned with the list/inspector dividers.
            .contentMargins(.top, 11, for: .scrollContent)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // The sidebar/list split divider: NavigationSplitView's own divider
        // renders zero-width on macOS 26+, so draw the same 1px separatorColor
        // hairline the inspector's ResizeDivider uses — full height, flush with
        // the sidebar's trailing edge.
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .ignoresSafeArea()
        }
        // The header row IS the title bar: lay the column out from the window's
        // top edge instead of below the system title-bar inset. All three columns
        // do this, so their header dividers align by construction — no measured
        // nudge constants (which broke whenever macOS changed its insets).
        .ignoresSafeArea(.container, edges: .top)
        .hidesTopScrollEdgeEffect()
    }
}

struct SidebarRow: View {
    let item: SidebarItem
    var count: Int?

    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .frame(width: 20)
                .font(.system(size: 13))
            Text(item.title)
                .font(.system(size: 13))
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .padding(.vertical, 2)
        .tag(ShelfSelection.builtin(item))
    }
}
