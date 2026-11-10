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
            Button {
                filter.language = ""
            } label: {
                choiceLabel("Any Language", on: filter.language.isEmpty)
            }
            if !languages.isEmpty { Divider() }
            ForEach(languages, id: \.name) { language in
                Button {
                    filter.language = language.name
                } label: {
                    choiceLabel("\(language.name)  \(language.count)",
                                on: filter.language.caseInsensitiveCompare(language.name) == .orderedSame)
                }
            }
            Divider()
            Button {
                filter.uiOnly.toggle()
            } label: {
                if filter.uiOnly {
                    Label("UI Only  \(uiCount)", systemImage: "checkmark")
                } else {
                    Label("UI Only  \(uiCount)", systemImage: ReshelfMarks.uiSymbol)
                }
            }
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

    @ViewBuilder
    private func choiceLabel(_ title: String, on: Bool) -> some View {
        if on {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
