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
    @Binding var selection: SidebarItem?
    @Query(sort: \ToolProject.name) private var allProjects: [ToolProject]

    /// Computed (not cached) so counts refresh on any catalog change — including a
    /// project moving between shelves, which changes status but not the count.
    private var filterCounts: SidebarFilterCounts {
        SidebarFilterCounts(projects: allProjects)
    }

    /// The sidebar column's content origin sits ~10pt lower than the detail
    /// column's (measured: sidebar top 42pt vs detail 32pt), so its header and
    /// divider would render 10pt below the list/inspector dividers. This negative
    /// nudge lifts the sidebar content to align all three header dividers into one
    /// continuous line.
    private static let headerTopAlignmentNudge: CGFloat = -10

    var body: some View {
        // Build the counts once per render (the struct rebuilds on each access).
        let counts = filterCounts
        let categories = SidebarItem.sidebarCategoryItems.filter {
            counts.count(for: $0) > 0 || selection == $0
        }
        return VStack(spacing: 0) {
            AlignedSplitColumnHeader {
                ReshelfBrandHeader()
            }
            .padding(.top, Self.headerTopAlignmentNudge)

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
        .tag(item)
    }
}
