import SwiftUI
import AppKit

/// Captures two-finger trackpad pan events for the canvas viewport and
/// forwards the deltas to a closure.
///
/// SwiftUI gestures don't see scrollWheel events, and a plain NSView
/// mounted via .background isn't always reached by the AppKit responder
/// chain when SwiftUI hosting views are above it. So we install a local
/// NSEvent monitor scoped to the view's window — it fires for every
/// scrollWheel event in that window, regardless of responder routing,
/// and we filter to events that land inside our view's frame.
///
/// Mouse-wheel scroll (`hasPreciseScrollingDeltas == false`) is left
/// alone so a mouse user keeps default behavior.
struct CanvasScrollCatcher: NSViewRepresentable {

    let onPan: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCatchView {
        let v = ScrollCatchView()
        v.onPan = onPan
        return v
    }

    func updateNSView(_ nsView: ScrollCatchView, context: Context) {
        nsView.onPan = onPan
    }

    final class ScrollCatchView: NSView {
        var onPan: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }

        // Monitor lifetime tracks "is this view mounted in a window?".
        // Adding in didMoveToWindow + removing in viewWillMove(toWindow: nil)
        // means we don't leak monitors across view rebuilds.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitorIfNeeded()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { removeMonitor() }
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self else { return event }
                // Only events from our window
                guard event.window === self.window else { return event }
                // Only trackpad gestures, not wheel
                guard event.hasPreciseScrollingDeltas else { return event }
                // Only events whose location falls inside our view's frame.
                // event.locationInWindow is in window coords; our frame in
                // window coords requires conversion through superview.
                let pointInWindow = event.locationInWindow
                let pointInSelf = self.convert(pointInWindow, from: nil)
                guard self.bounds.contains(pointInSelf) else { return event }

                self.onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
                return nil   // consumed; don't bubble (would otherwise scroll panels)
            }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { removeMonitor() }
    }
}
