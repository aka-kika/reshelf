# Sidebar polish: a little Liquid Glass (desktop)

Kika, 2026-10-03: "side bar feels 5 years behind ... plan a polish more liquid glass, not too much but to feel more modern."

Status: plan only. Needs Kika's yes on a mockup before code (her rule: reference first, then mockup).

## In one minute

The sidebar is already built the modern way (`NavigationSplitView` + `List` with `.listStyle(.sidebar)`). On macOS 26 that alone gives the floating Liquid Glass sidebar. reshelf hides it: `SidebarView.swift:160` paints `Color(nsColor: .windowBackgroundColor)` over the column, and `.scrollContentBackground(.hidden)` drops the list's own material. Taking those off (on macOS 26 only) is most of the win. The rest is small: lighter rows, no grey count boxes, empty sections gone, a shorter tag list.

## What it looks like today (captured 2026-10-03)

- Flat grey column, same grey as the window: no depth, no edge.
- Counts sit in grey rounded boxes (`RoundedRectangle(cornerRadius: 4)` in `SidebarRow` / `TagSidebarRow`): the oldest-looking detail.
- "Folders" and "Categories" headers show with nothing under them.
- A long `#` tag list (macos 395, swift 321 ...) takes most of the height.
- Library icons are plain grey outlines.

## References from the shelf

- **ApolloShell** (The Collector, cloned, `~/reshelf/repos/macOS/ApolloShell`, built for macOS 26): `Sources/ApolloShell/NexusView.swift`. A plain `NavigationSplitView` + sidebar `List`, no background on the column: "the Liquid Glass of the sidebar comes from macOS 26 itself". Small rounded colored icon tiles (`NexusTile`, 22 pt) next to each row. License: check its LICENSE before lifting code; the pattern is free to use.
- **syrtis** (Top Shelf, cloned, MIT): `Sources/Syrtis/Views/SettingsWindowView.swift`. Footer goes in the list's own `safeAreaInset` so it keeps the sidebar material; a `Divider().ignoresSafeArea(edges: .top)` so the seam reaches the top. `GlassBackground.swift` shows the `#available` guard for glass with an older deployment target.
- **talaria** (Top Shelf, not cloned, MIT): native Hermes client in SwiftUI + Liquid Glass. Worth a look at its sidebar if we want a second opinion; clone only on Kika's yes.

## The plan (small steps, each one shippable)

1. **Let the system glass through (macOS 26 only).** In `SidebarView`, skip `.background(windowBackgroundColor)` and `.scrollContentBackground(.hidden)` when `#available(macOS 26, *)`; keep them for 14 and 15. Check `MainWindowChromeConfigurator` (`window.backgroundColor`, transparent title bar) does not flatten it. Result: the sidebar floats as an inset glass panel with rounded corners, the list and inspector stay flat (her "inspector-style flat panels" preference).
2. **Counts without boxes.** Use the native `.badge(count)` on the row, or plain `.secondary` text with `.monospacedDigit()`, no background. Lighter and current.
3. **Library icons with a hint of color.** Keep SF Symbols, give each Library row one quiet tint (Top Shelf star, Cloned drive ...), using `.symbolRenderingMode(.hierarchical)`. No tiles unless the mockup shows they help. Max three pastel tones, matching the app icon.
4. **Hide empty sections.** Folders and Categories show only when they have rows, or one quiet "New folder" row.
5. **Tags: shorter.** Show the top 8 tags, then "Show all 40" to expand. Drop the `#` glyph for a lighter `tag` symbol or no icon.
6. **Footer and seam.** If a footer is added later, put it in the list's `safeAreaInset` (syrtis pattern) so it keeps the glass.
7. **Verify on macOS 26 and on 14/15** (deployment target is 14.0): light and dark, a bright wallpaper behind, and the window narrow and wide. Capture before and after.

Not in scope: glass on the project list, the inspector or cards (too much glass), new navigation, search moved into the sidebar.

## Mockup first

Before code: a before/after mockup of the sidebar only (steps 1 to 5), shown to Kika. Code starts on a branch after her yes.
