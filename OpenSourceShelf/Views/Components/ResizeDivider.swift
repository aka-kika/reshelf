import SwiftUI
import AppKit

// Native AppKit drag handle for the inspector column.
// Uses mouseDragged: directly — no SwiftUI gesture competition with NavigationSplitView.
// Reports isDragging so the caller can apply a blur during resize to mask text reflow.
struct ResizeDivider: NSViewRepresentable {
    @Binding var width: CGFloat
    @Binding var isDragging: Bool
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(width: $width, isDragging: $isDragging, minWidth: minWidth, maxWidth: maxWidth)
    }

    func makeNSView(context: Context) -> ResizeDividerNSView {
        let view = ResizeDividerNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ResizeDividerNSView, context: Context) {
        context.coordinator.minWidth = minWidth
        context.coordinator.maxWidth = maxWidth
    }

    final class Coordinator {
        var width: Binding<CGFloat>
        var isDragging: Binding<Bool>
        var minWidth: CGFloat
        var maxWidth: CGFloat

        init(width: Binding<CGFloat>, isDragging: Binding<Bool>, minWidth: CGFloat, maxWidth: CGFloat) {
            self.width = width
            self.isDragging = isDragging
            self.minWidth = minWidth
            self.maxWidth = maxWidth
        }
    }
}

final class ResizeDividerNSView: NSView {
    weak var coordinator: ResizeDivider.Coordinator?

    // Anchor the drag in WINDOW coordinates, not the view's local space.
    // The divider slides left as the inspector widens, so converting to local
    // coords makes the view chase the cursor and the per-frame delta collapses
    // to ~0 (the jitter). Window coords are a fixed reference: the window isn't
    // moving, so total delta since mouse-down is stable and the resize is smooth.
    private var startWindowX: CGFloat = 0
    private var startWidth: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 8, height: NSView.noIntrinsicMetric) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        startWindowX = event.locationInWindow.x
        startWidth = coordinator?.width.wrappedValue ?? 0
        coordinator?.isDragging.wrappedValue = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coord = coordinator else { return }
        // Inspector lives on the trailing edge: dragging left (smaller x) widens it.
        let delta = event.locationInWindow.x - startWindowX
        let newWidth = max(coord.minWidth, min(coord.maxWidth, startWidth - delta))
        coord.width.wrappedValue = newWidth
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.isDragging.wrappedValue = false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
}
