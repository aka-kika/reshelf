import SwiftUI

/// The Language button next to Sort, the same on every list (round 3). Just
/// the icon until a language or UI only is picked; then the name shows beside
/// it (Kika's pick on the mockup, 11 Nov).
struct LanguageFilterMenu: View {
    @Binding var filter: ListFilter
    /// The languages in the list as the sidebar, search or fits left it.
    let languages: [(name: String, count: Int)]
    /// How many repos in that list carry the UI mark.
    let uiCount: Int

    var body: some View {
        Menu {
            // A picker, like Sort: the menu draws the tick on the picked one
            // (images in these menus are not shown, so a checkmark label was blank).
            Picker("Language", selection: $filter.language) {
                Text("Any Language").tag("")
                ForEach(languages, id: \.name) { language in
                    Text("\(language.name)  \(language.count)").tag(language.name)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Toggle("UI Only  \(uiCount)", isOn: $filter.uiOnly)
                .help("Only repos whose UI you like")
            if filter.isActive {
                Divider()
                Button("Clear Filter") { filter = ListFilter() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12))
                if filter.isActive {
                    Text(filter.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, filter.isActive ? 6 : 0)
            .frame(minWidth: 24, minHeight: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(filter.isActive ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(filter.isActive ? "Language: \(filter.title)" : "Language")
        .titlebarClickable()
    }
}
