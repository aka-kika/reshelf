import AppKit
import SwiftUI

enum ShelfWindowChrome {
    static func apply(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar?.displayMode = .iconOnly
        // Drop the system title-bar separator (the faint light-gray line macOS
        // draws across the top under full-size content). Our own aligned header
        // hairline sits lower, under the column header row, and stays.
        window.titlebarSeparatorStyle = .none
        // Opaque dark base so nothing translucent samples the bright desktop and
        // bleeds a light line along the top edge.
        window.backgroundColor = .windowBackgroundColor
    }

    /// Replace the heavy macOS sidebar split divider (shadowed, "Finder" look)
    /// with a clean 1px hairline so it matches the inspector's ResizeDivider.
    /// The NSSplitView backing NavigationSplitView can appear a few frames after
    /// the window is first configured, so retry across a short window.
    static func flattenSidebarDivider(in window: NSWindow, attemptsRemaining: Int = 8) {
        // Re-assert each pass: SwiftUI rebuilds the toolbar after the one-time
        // apply() and can restore the system title-bar separator line.
        window.titlebarSeparatorStyle = .none

        guard let contentView = window.contentView else { return }
        let splitViews = contentView.descendantSplitViews()

        for splitView in splitViews {
            splitView.dividerStyle = .thin
            clearShadow(on: splitView)
            // The sidebar drop shadow is drawn by the arranged sidebar view
            // (and its enclosing clip/scroll views), not the split view itself.
            for arranged in splitView.arrangedSubviews {
                clearShadow(on: arranged)
                for descendant in arranged.allDescendants() {
                    clearShadow(on: descendant)
                }
            }
        }

        flattenChromeMaterials(in: window)

        // Keep re-applying briefly: SwiftUI rebuilds can restore the shadow.
        if attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                flattenSidebarDivider(in: window, attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    /// macOS gives the NavigationSplitView sidebar a vibrant inset panel and the
    /// title-bar band its own faint material — together they read as two extra
    /// shades of gray at the top of the window. Swap both for a flat
    /// window-background material so the sidebar and the title-bar strip match
    /// the rest of the window (one continuous surface, like Claude). The title-bar
    /// effect view lives in the window's frame view (the content view's superview),
    /// so we traverse from there too.
    private static func flattenChromeMaterials(in window: NSWindow) {
        let targets: Set<NSVisualEffectView.Material> = [.sidebar, .titlebar, .headerView]
        let roots = [window.contentView, window.contentView?.superview].compactMap { $0 }
        for root in roots {
            for effectView in root.descendantVisualEffectViews()
            where targets.contains(effectView.material) {
                effectView.material = .windowBackground
                // .withinWindow (not .behindWindow): don't sample the desktop —
                // that's what bled a light line along the top edge.
                effectView.blendingMode = .withinWindow
                effectView.state = .followsWindowActiveState
            }
        }
    }

    private static func clearShadow(on view: NSView) {
        view.shadow = nil
        if view.wantsLayer {
            view.layer?.shadowOpacity = 0
            view.layer?.shadowRadius = 0
            view.layer?.shadowColor = NSColor.clear.cgColor
        }
    }
}

private extension NSView {
    /// Depth-first collection of all NSSplitView instances in the subtree.
    func descendantSplitViews() -> [NSSplitView] {
        var result: [NSSplitView] = []
        for subview in subviews {
            if let splitView = subview as? NSSplitView {
                result.append(splitView)
            }
            result.append(contentsOf: subview.descendantSplitViews())
        }
        return result
    }

    /// Depth-first collection of every descendant view in the subtree.
    func allDescendants() -> [NSView] {
        var result: [NSView] = []
        for subview in subviews {
            result.append(subview)
            result.append(contentsOf: subview.allDescendants())
        }
        return result
    }

    /// Depth-first collection of all NSVisualEffectView instances in the subtree.
    func descendantVisualEffectViews() -> [NSVisualEffectView] {
        var result: [NSVisualEffectView] = []
        for subview in subviews {
            if let effectView = subview as? NSVisualEffectView {
                result.append(effectView)
            }
            result.append(contentsOf: subview.descendantVisualEffectViews())
        }
        return result
    }
}

/// One-time main window chrome (title bar). The sidebar divider is left
/// free-dragging — width bounds come from `navigationSplitViewColumnWidth`.
struct MainWindowChromeConfigurator: NSViewRepresentable {
    final class Coordinator: NSObject {
        var configuredWindowID: ObjectIdentifier?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        let windowID = ObjectIdentifier(window)
        guard context.coordinator.configuredWindowID != windowID else { return }
        context.coordinator.configuredWindowID = windowID
        ShelfWindowChrome.apply(to: window)
        // Defer the divider pass: the NSSplitView backing NavigationSplitView
        // isn't in the hierarchy yet during the first configuration pass.
        DispatchQueue.main.async {
            ShelfWindowChrome.flattenSidebarDivider(in: window)
        }
    }
}
