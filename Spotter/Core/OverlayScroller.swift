import AppKit
import SwiftUI

extension View {
    func overlayScroller() -> some View {
        background(OverlayScrollerConfigurator(searchesDescendants: false).frame(width: 0, height: 0))
    }

    /// The same forced overlay style for a container that owns its scroll view *below* this view
    /// instead of around it — a `Form`, whose `NSScrollView` is a sibling of the probe, never an
    /// ancestor of it.
    func containerOverlayScroller() -> some View {
        background(OverlayScrollerConfigurator(searchesDescendants: true).frame(width: 0, height: 0))
    }
}

private struct OverlayScrollerConfigurator: NSViewRepresentable {
    let searchesDescendants: Bool

    func makeNSView(context: Context) -> NSView { ProbeView(searchesDescendants: searchesDescendants) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.applyOverlayStyle()
    }

    private final class ProbeView: NSView {
        private var attemptsRemaining = 12
        private var styleObserver: NotificationToken?
        private let searchesDescendants: Bool

        init(searchesDescendants: Bool) {
            self.searchesDescendants = searchesDescendants
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                styleObserver = nil
                return
            }
            observeStyleChanges()
            attemptsRemaining = 12  // re-attached to a fresh hierarchy; give the splice a few ticks again
            applyOverlayStyle()
        }

        /// AppKit resets scroller style back to the system preference on this notification, so re-apply on the next tick after its own handler runs.
        private func observeStyleChanges() {
            guard styleObserver == nil else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
            styleObserver = NotificationToken(token, center: .default)
        }

        /// The scroll view a sibling container owns. Bounded on both axes: only a few hops up, and
        /// the first match wins, so the search can never wander out to the pane's own sidebar.
        private var containedScrollView: NSScrollView? {
            var ancestor = superview
            var hops = 0
            while let current = ancestor, hops < 2 {
                if let found = Self.firstScrollView(in: current) { return found }
                ancestor = current.superview
                hops += 1
            }
            return nil
        }

        private static func firstScrollView(in view: NSView) -> NSScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? NSScrollView { return scrollView }
                if let nested = firstScrollView(in: subview) { return nested }
            }
            return nil
        }

        func applyOverlayStyle() {
            guard let scrollView = searchesDescendants ? containedScrollView : enclosingScrollView
            else {
                // Not spliced into the scroll view yet; retry next tick, bounded so a view that never lands in one can't spin the main thread.
                guard attemptsRemaining > 0 else { return }
                attemptsRemaining -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            guard scrollView.scrollerStyle != .overlay || !scrollView.autohidesScrollers else {
                return  // already in the target state — don't churn layout on re-runs
            }
            scrollView.scrollerStyle = .overlay  // thin floating knob that reserves no width
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            scrollView.tile()  // reclaim any gutter the legacy scroller had reserved, same layout pass
        }
    }
}
