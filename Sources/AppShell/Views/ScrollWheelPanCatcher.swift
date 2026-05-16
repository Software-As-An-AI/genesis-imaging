import SwiftUI
import AppKit

/// Captures trackpad gesture events (scroll for pan, pinch for zoom) while
/// a SwiftUI view is on screen, forwarding them as deltas to closures.
///
/// Implementation note (2026-05-16 dev-test bug): An earlier attempt used
/// a transparent NSViewRepresentable with `hitTest → nil`. That works in
/// packaged signed apps but NOT in `swift run` bare-binary dev builds —
/// AppKit's scroll routing depends on hit-test results and the SwiftUI
/// Canvas underneath has no handler, so events dropped. SwiftUI's native
/// `MagnificationGesture` had the same dev-vs-packaged disparity.
///
/// `NSEvent.addLocalMonitorForEvents` sidesteps the routing problem:
/// monitor receives all matching events on the active window before
/// dispatch. We check the cursor is inside the view's global frame, then
/// forward + consume (return nil), otherwise pass through (return event).
///
/// Both pan (`scrollWheel`) and zoom (`magnify`) handled in one monitor.
struct TrackpadGestureCatcher: View {
    let onScrollPan: (CGFloat, CGFloat) -> Void
    let onMagnify: (CGFloat) -> Void
    let onMagnifyEnd: () -> Void

    @State private var monitor: Any? = nil
    @State private var globalBounds: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    updateBounds(geo)
                    install()
                }
                .onDisappear { uninstall() }
                .onChange(of: geo.frame(in: .global)) { _, _ in updateBounds(geo) }
        }
    }

    private func updateBounds(_ geo: GeometryProxy) {
        globalBounds = geo.frame(in: .global)
    }

    private func install() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.scrollWheel, .magnify]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            // Filter: cursor must be inside the view's screen frame.
            guard isInside(event: event) else { return event }

            switch event.type {
            case .scrollWheel:
                onScrollPan(event.scrollingDeltaX, event.scrollingDeltaY)
                return nil
            case .magnify:
                onMagnify(event.magnification)
                if event.phase == .ended || event.phase == .cancelled {
                    onMagnifyEnd()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func isInside(event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let inWindow = event.locationInWindow
        let onScreen = window.convertPoint(toScreen: inWindow)
        let screenHeight = window.screen?.frame.height ?? 0
        let flippedY = screenHeight - onScreen.y
        return globalBounds.contains(CGPoint(x: onScreen.x, y: flippedY))
    }

    private func uninstall() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
