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
        installTitlebarClickRouter(in: window)
    }

    /// The header row is overlaid by the system title-bar view, which claims real
    /// mouse clicks as window drags before they can reach the SwiftUI controls
    /// underneath (keyboard shortcuts are unaffected). Views hosted inside a
    /// titlebar accessory DO receive real clicks, so a transparent router
    /// accessory covers the band and forwards clicks over interactive controls
    /// (marked with `.titlebarClickable()`) down to the content. Everywhere else
    /// it stays hit-transparent so the header still drags the window.
    /// SwiftUI can rebuild the toolbar and drop foreign accessories — re-assert
    /// on every call (cheap contains check).
    static func installTitlebarClickRouter(in window: NSWindow) {
        let installed = window.titlebarAccessoryViewControllers.contains {
            $0.view is TitlebarClickRouterView
        }
        guard !installed else { return }
        let controller = NSTitlebarAccessoryViewController()
        let router = TitlebarClickRouterView(
            frame: NSRect(x: 0, y: 0, width: window.frame.width, height: 28)
        )
        router.autoresizingMask = [.width]
        controller.view = router
        controller.layoutAttribute = .right
        controller.fullScreenMinHeight = 0
        window.addTitlebarAccessoryViewController(controller)
    }

    /// Replace the heavy macOS sidebar split divider (shadowed, "Finder" look)
    /// with a clean 1px hairline so it matches the inspector's ResizeDivider.
    /// The NSSplitView backing NavigationSplitView can appear a few frames after
    /// the window is first configured, so retry across a short window.
    static func flattenSidebarDivider(in window: NSWindow, attemptsRemaining: Int = 20) {
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
        hideTitlebarBackdrops(in: window)

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

    /// macOS 26+ ("Liquid Glass") draws the title-bar band with private
    /// `NSTitlebarBackgroundView` layers (hosting an `NSScrollPocket`) added as
    /// direct subviews of the NSSplitView — they are NOT NSVisualEffectViews, so
    /// the material pass above misses them. They dim/gray the top strip where our
    /// column headers live (verified live: hiding them restores the headers).
    /// AppKit creates them lazily and re-shows them, so this runs cheaply on every
    /// window draw (the backdrops are direct split-view children — no deep walk)
    /// and each found view gets a KVO guard that instantly reverts re-shows.
    private static var backdropGuards: [ObjectIdentifier: NSKeyValueObservation] = [:]

    static func hideTitlebarBackdrops(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        for splitView in contentView.descendantSplitViews() {
            for view in splitView.subviews
            where String(describing: type(of: view)).contains("NSTitlebarBackgroundView") {
                view.isHidden = true
                let key = ObjectIdentifier(view)
                if backdropGuards[key] == nil {
                    backdropGuards[key] = view.observe(\.isHidden) { view, _ in
                        if !view.isHidden { view.isHidden = true }
                    }
                }
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
///
/// Configuration hangs off `viewDidMoveToWindow`, NOT `updateNSView`: this
/// representable has no SwiftUI inputs, so on macOS 26+ SwiftUI never calls
/// `updateNSView` again after the initial (window-less) pass — the old
/// updateNSView-based configuration silently stopped running there.
struct MainWindowChromeConfigurator: NSViewRepresentable {
    final class ChromeConfiguringView: NSView {
        private var configuredWindowID: ObjectIdentifier?
        private var appearanceObservation: NSKeyValueObservation?
        private var windowNotificationTokens: [NSObjectProtocol] = []

        deinit {
            windowNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let windowID = ObjectIdentifier(window)
            guard configuredWindowID != windowID else { return }
            configuredWindowID = windowID
            ShelfWindowChrome.apply(to: window)
            // Defer the divider pass: the NSSplitView backing NavigationSplitView
            // isn't in the hierarchy yet during the first configuration pass.
            DispatchQueue.main.async {
                ShelfWindowChrome.flattenSidebarDivider(in: window)
            }
            // Switching light/dark rebuilds the system chrome (titlebar backdrop,
            // glass materials) — re-flatten whenever the appearance flips.
            appearanceObservation = window.observe(\.effectiveAppearance) { [weak window] _, _ in
                guard let window else { return }
                DispatchQueue.main.async {
                    ShelfWindowChrome.flattenSidebarDivider(in: window, attemptsRemaining: 4)
                }
            }
            // The backdrop layers are created lazily, well after launch — re-assert
            // the hide on every window draw (cheap: direct split-view children only).
            windowNotificationTokens.forEach(NotificationCenter.default.removeObserver)
            windowNotificationTokens = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification, object: window, queue: .main
                ) { [weak window] _ in
                    guard let window else { return }
                    ShelfWindowChrome.hideTitlebarBackdrops(in: window)
                    ShelfWindowChrome.installTitlebarClickRouter(in: window)
                }
            ]
        }
    }

    func makeNSView(context: Context) -> NSView {
        ChromeConfiguringView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Title-bar click routing

/// Weak registry of the invisible anchors that mark interactive header controls.
/// The router accessory resolves their live window frames at hit-test time, so
/// divider drags, sidebar collapse, and screen switches need no bookkeeping.
final class TitlebarClickAnchorRegistry {
    static let shared = TitlebarClickAnchorRegistry()
    private let anchors = NSHashTable<TitlebarClickAnchorView>.weakObjects()

    func register(_ anchor: TitlebarClickAnchorView) {
        anchors.add(anchor)
    }

    /// The live anchors currently attached in `window`.
    func liveAnchors(in window: NSWindow) -> [TitlebarClickAnchorView] {
        anchors.allObjects.filter { anchor in
            anchor.window === window && anchor.superview != nil
                && !anchor.convert(anchor.bounds, to: nil).isEmpty
        }
    }

    /// Window-coordinate frames of the registered controls in `window`.
    func controlFrames(in window: NSWindow) -> [NSRect] {
        liveAnchors(in: window).map { $0.convert($0.bounds, to: nil) }
    }
}

/// Invisible, hit-transparent view overlaid on an interactive header control:
/// publishes that control's frame to the registry and carries the action the
/// click-router should fire when a real click lands there. (Replaying raw
/// mouse events into SwiftUI's hosting view does nothing — SwiftUI routes
/// events at the window level — so the anchor triggers semantics directly.)
final class TitlebarClickAnchorView: NSView {
    /// Fired on click for plain buttons. nil → menu-style control: the router
    /// finds the AppKit control under the point and `performClick`s it.
    var clickAction: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            TitlebarClickAnchorRegistry.shared.register(self)
        }
    }
}

private struct TitlebarClickAnchor: NSViewRepresentable {
    var action: (() -> Void)?

    func makeNSView(context: Context) -> TitlebarClickAnchorView {
        let view = TitlebarClickAnchorView()
        view.clickAction = action
        return view
    }

    func updateNSView(_ nsView: TitlebarClickAnchorView, context: Context) {
        nsView.clickAction = action
    }
}

extension View {
    /// Mark an interactive control that sits in the merged title-bar/header row.
    /// Without this, the system title-bar view claims real mouse clicks on the
    /// control as window drags (keyboard equivalents still work). Pass the
    /// control's action for plain buttons; omit it for menus (the router opens
    /// the underlying AppKit popup natively). See
    /// `ShelfWindowChrome.installTitlebarClickRouter`.
    func titlebarClickable(action: (() -> Void)? = nil) -> some View {
        overlay(TitlebarClickAnchor(action: action).allowsHitTesting(false))
    }
}

/// Transparent accessory view spanning the title-bar band. Claims hits only
/// over registered control frames (via `TitlebarClickHoleView`s, which are also
/// carved out of the window-drag region by `mouseDownCanMoveWindow == false`);
/// everywhere else it returns nil so the title bar keeps dragging the window.
final class TitlebarClickRouterView: NSView {
    private var holes: [TitlebarClickHoleView] = []
    /// Clones of AppKit's own `NSTitlebarContainerBlockingView` — the private
    /// primitive AppKit plants over the sidebar split divider to carve a spot
    /// out of the window-drag region. The drag decision is made from standing
    /// view geometry (hitTest is never consulted for it), so we place one over
    /// each interactive control, exactly like AppKit does for the divider.
    private var blockingViews: [NSView] = []
    private static let blockingViewClass: NSView.Type? =
        NSClassFromString("NSTitlebarContainerBlockingView") as? NSView.Type
    private var syncTimer: Timer?

    override var mouseDownCanMoveWindow: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncTimer?.invalidate()
        syncTimer = nil
        blockingViews.forEach { $0.removeFromSuperview() }
        blockingViews.removeAll()
        guard window != nil else { return }
        // The window-drag decision is made from STANDING view geometry, so the
        // hole/blocker frames must be correct at rest, not just at click time.
        // AppKit repositions the accessory after any notification we could hook,
        // so a cheap watchdog keeps the standing frames true (4 rect conversions
        // per tick; writes only when a frame actually changed).
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.syncHoles(syncBlockingViews: true)
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
        syncHoles(syncBlockingViews: true)
    }

    override func layout() {
        super.layout()
        syncHoles(syncBlockingViews: true)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        syncHoles(syncBlockingViews: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncHoles(syncBlockingViews: false)
    }

    deinit {
        syncTimer?.invalidate()
        blockingViews.forEach { $0.removeFromSuperview() }
    }

    /// NSTitlebarContainerView, where AppKit parks its own blocking views.
    private var titlebarContainer: NSView? {
        var view: NSView? = superview
        while let v = view {
            if String(describing: type(of: v)).contains("NSTitlebarContainerView") {
                return v
            }
            view = v.superview
        }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview, window != nil else { return nil }
        syncHoles(syncBlockingViews: false)
        let windowPoint = superview.convert(point, to: nil)
        let localPoint = convert(windowPoint, from: nil)
        return holes.first { !$0.frame.isEmpty && $0.frame.contains(localPoint) }
    }

    private func syncHoles(syncBlockingViews: Bool) {
        guard let window else { return }
        let anchors = TitlebarClickAnchorRegistry.shared.liveAnchors(in: window)
        let frames = anchors.map { $0.convert($0.bounds, to: nil) }
        while holes.count < anchors.count {
            let hole = TitlebarClickHoleView()
            addSubview(hole)
            holes.append(hole)
        }
        while holes.count > anchors.count {
            holes.removeLast().removeFromSuperview()
        }
        for (hole, (anchor, frame)) in zip(holes, zip(anchors, frames)) {
            hole.anchor = anchor
            let local = convert(frame, from: nil).intersection(bounds)
            let clipped = local.isNull ? .zero : local
            if hole.frame != clipped {
                hole.frame = clipped
            }
        }
        if syncBlockingViews {
            syncDragRegionBlockers(controlFrames: frames)
        }
    }

    /// Mirror the control frames with AppKit's own drag-region carve-out views,
    /// parked at the same level of the hierarchy AppKit uses for its own.
    /// Never called from `hitTest` (no hierarchy mutation mid-hit-testing).
    private func syncDragRegionBlockers(controlFrames: [NSRect]) {
        guard let blockingClass = Self.blockingViewClass,
              let container = titlebarContainer else { return }
        while blockingViews.count < controlFrames.count {
            let blocker = blockingClass.init(frame: .zero)
            // Bottom of the container: carves the drag region (that's standing
            // geometry, z-independent) without ever winning hit-testing — the
            // router's holes above stay the event handler.
            container.addSubview(blocker, positioned: .below, relativeTo: nil)
            blockingViews.append(blocker)
        }
        while blockingViews.count > controlFrames.count {
            blockingViews.removeLast().removeFromSuperview()
        }
        for (blocker, frame) in zip(blockingViews, controlFrames) {
            if blocker.superview !== container {
                container.addSubview(blocker, positioned: .below, relativeTo: nil)
            }
            let local = container.convert(frame, from: nil)
            if blocker.frame != local {
                blocker.frame = local
            }
        }
    }
}

/// One transparent "hole" per interactive header control. Receives the real
/// mouse events in the title-bar layer and triggers the control's semantics:
/// the anchor's action closure for plain buttons (replaying raw events into
/// SwiftUI is a no-op — it routes events at the window level), or a native
/// `performClick` on the AppKit popup that backs a SwiftUI Menu. An NSButton
/// (not a plain NSView) so the window-drag region builder recognizes it as an
/// interactive control; it draws nothing and never runs button tracking (no
/// super calls in the mouse handlers).
final class TitlebarClickHoleView: NSButton {
    weak var anchor: TitlebarClickAnchorView?
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        isTransparent = true
        refusesFirstResponder = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Invisible catcher: don't let the system show its control/button pointer —
    /// the plain arrow, as over the visible SwiftUI controls underneath.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        if anchor?.clickAction != nil {
            // Plain button: fire on mouse-up inside, like a real button.
            isPressed = true
            return
        }
        // Menu-style control: open the backing AppKit popup now (native feel).
        underlyingControl(at: event.locationInWindow)?.performClick(nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer { isPressed = false }
        guard isPressed, let action = anchor?.clickAction else { return }
        let local = convert(event.locationInWindow, from: nil)
        if bounds.insetBy(dx: -4, dy: -4).contains(local) {
            action()
        }
    }

    /// Nearest AppKit control in the content hierarchy under a window point
    /// (e.g. the SwiftUIPopupButton backing a SwiftUI Menu).
    private func underlyingControl(at locationInWindow: NSPoint) -> NSControl? {
        guard let window, let contentView = window.contentView else { return nil }
        let root = contentView.superview ?? contentView
        var view = contentView.hitTest(root.convert(locationInWindow, from: nil))
        while let current = view {
            if let control = current as? NSControl {
                return control
            }
            view = current.superview
        }
        return nil
    }
}
