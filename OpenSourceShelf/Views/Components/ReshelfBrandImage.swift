import AppKit
import SwiftUI

enum ReshelfBrandImage {
    static var nsImage: NSImage? {
        // Use the app's own icon so the sidebar brand always matches AppIcon.
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            return appIcon
        }
        // Fall back to the bundled brand PNG if the app icon isn't available.
        if let url = Bundle.main.url(forResource: "ReshelfBrand", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}

/// The owl's face in one color (round 3, Kika: "reshelf mon icon"), for the
/// Reshelfed row and marks. A template image, so it takes the text color
/// like an SF Symbol. Made from AppIcon.png: the face without the ring.
enum ReshelfOwlGlyph {
    static let nsImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "ReshelfOwlGlyph", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()
}

/// The one-color owl as a view; it takes the foreground style like a symbol.
struct ReshelfOwlMark: View {
    var size: CGFloat = 13

    var body: some View {
        if let image = ReshelfOwlGlyph.nsImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "checkmark.seal")
                .font(.system(size: size * 0.85))
        }
    }
}

/// The UI mark's look, shared by the list row, the menu and the inspector
/// (Kika picked the brush, 11 Nov).
enum ReshelfMarks {
    static let uiSymbol = "paintbrush.pointed"
    /// A quiet lavender, like the sidebar's shelf tints.
    static let uiTint = Color(red: 0.61, green: 0.56, blue: 0.82)
}
