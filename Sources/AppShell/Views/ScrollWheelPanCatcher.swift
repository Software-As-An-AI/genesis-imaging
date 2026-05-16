import SwiftUI
import AppKit

/// Transparent NSViewRepresentable that captures `scrollWheel` events
/// (trackpad two-finger drag, mouse scroll) and forwards them to a
/// closure as `(dx, dy)` deltas in view-space points.
///
/// Used by `EraserEditorView` so the customer can pan around the canvas
/// with a two-finger trackpad gesture after zooming in — no mode-switch
/// to "Pan" tool required. Closure receives raw deltas; the editor
/// applies them to its `pan` state.
///
/// The hosting NSView is **non-blocking for hit testing** (`hitTest`
/// returns nil), so clicks/drags pass through to the SwiftUI Canvas
/// underneath. Scroll events are still routed here because AppKit's
/// scroll dispatch walks the responder chain, not just the hit chain.
struct ScrollWheelPanCatcher: NSViewRepresentable {
    /// Closure invoked on every scroll wheel event. `(dx, dy)` are
    /// `scrollingDeltaX` / `scrollingDeltaY` from `NSEvent` — positive
    /// dx = swipe right, positive dy = swipe down (macOS natural).
    let onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Transparent to pointer hit — clicks fall through to the
            // SwiftUI Canvas below.
            nil
        }

        override func scrollWheel(with event: NSEvent) {
            // Natural macOS: dy > 0 = content moves down (i.e., view of
            // content scrolls up). For a pan gesture we want the image
            // to follow the fingers, so we forward delta as-is and the
            // editor decides direction.
            onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }
}
