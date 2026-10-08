import AppKit

@MainActor
final class WindowDragCursor {
    private weak var view: NSView?
    private weak var window: NSWindow?
    private var timer: Timer?
    private var restoresCursorRects = false
    private var onEnd: (() -> Void)?

    func begin(in view: NSView, onEnd: (() -> Void)? = nil) {
        guard timer == nil, let window = view.window else { return }
        self.view = view
        self.window = window
        self.onEnd = onEnd
        restoresCursorRects = window.areCursorRectsEnabled
        window.disableCursorRects()
        NSCursor.closedHand.push()
        // Native window dragging returns immediately and may consume mouse-up, so watch the physical button too.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update(isPressed: NSEvent.pressedMouseButtons & 1 != 0)
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func update(isPressed: Bool) {
        guard timer != nil else { return }
        guard isPressed, let window, window.isVisible, view?.window === window else {
            end()
            return
        }
        NSCursor.closedHand.set()
    }

    func end() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        NSCursor.pop()
        if restoresCursorRects { window?.enableCursorRects() }
        if let view { window?.invalidateCursorRects(for: view) }
        view = nil
        window = nil
        let completion = onEnd
        onEnd = nil
        completion?()
    }
}
