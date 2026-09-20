import SwiftUI

struct WorldClockMapInteraction: NSViewRepresentable {
    let query: String
    let begin: () -> Int
    let update: (Int) -> Void
    let end: () -> Void

    func makeNSView(context: Context) -> InteractionView { InteractionView(frame: .zero) }

    func updateNSView(_ view: InteractionView, context: Context) {
        if view.query != query {
            view.finishDrag()
            view.scroll = WorldClockScrollAccumulator()
        }
        view.query = query
        view.begin = begin
        view.update = update
        view.end = end
    }

    static func dismantleNSView(_ view: InteractionView, coordinator: ()) { view.finishDrag() }

    final class InteractionView: NSView {
        var query = ""
        var begin: () -> Int = { 0 }
        var update: (Int) -> Void = { _ in }
        var end: () -> Void = {}
        var scroll = WorldClockScrollAccumulator()
        private var dragStart: (x: CGFloat, minutes: Int)?
        private var lastScrollTime: TimeInterval = 0

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            finishDrag()
            scroll = WorldClockScrollAccumulator()
            dragStart = (event.locationInWindow.x, begin())
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart else { return }
            update(dragStart.minutes + WorldClockMapGeometry.dragMinutes(
                translation: event.locationInWindow.x - dragStart.x))
        }

        override func mouseUp(with event: NSEvent) { finishDrag() }

        func finishDrag() {
            guard dragStart != nil else { return }
            dragStart = nil
            NSCursor.pop()
            end()
        }

        override func scrollWheel(with event: NSEvent) {
            guard dragStart == nil else { return }
            if event.phase.contains(.began) || event.timestamp - lastScrollTime > 0.3 {
                scroll = WorldClockScrollAccumulator()
            }
            lastScrollTime = event.timestamp
            // AppKit already applies the user's natural-scrolling preference, including momentum events.
            let minutes = scroll.consume(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            guard minutes != 0 else { return }
            let start = begin()
            update(start + minutes)
            end()
        }
    }
}
