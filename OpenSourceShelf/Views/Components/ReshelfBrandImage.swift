import AppKit

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
