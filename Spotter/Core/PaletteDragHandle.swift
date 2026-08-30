import AppKit

/// The palette's only move affordance: a transparent strip across the top of the panel frame whose
/// centered grab pill fades in when the pointer nears the top edge. It lives *inside* the palette
/// window (the frame is one strip taller than the visible glass) so a grab hands the real event to
/// the window server via `performDrag` — the native path that keeps every input region valid.
/// Moving the panel with per-step `setFrameOrigin`, or floating the pill in its own window, leaves
/// window-server input shapes behind: windows that still draw correctly but take no clicks.
/// The strip's transparent pixels are click-through at the server, so the sliver of desktop above
/// the glass stays clickable while the pill is hidden; only the pill's own drawn pixels grab.
final class PaletteDragHandleView: NSView {
    /// Extra frame height above the glass: the pill's lane plus its gap to the top edge.
    static let stripHeight: CGFloat = 26

    private static let clickSlop: CGFloat = 3

    /// A plain click (never a drag) re-centers the palette.
    var onClick: (() -> Void)?

    private let pill = PalettePillView()
    private var hideTimer: Timer?
    private var dragStart: NSPoint?
    private var didDrag = false

    init() {
        super.init(frame: .zero)
        pill.alphaValue = 0
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        pill.frame = NSRect(x: bounds.midX - 32, y: bounds.midY - 7, width: 64, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { reveal() }
    override func mouseExited(with event: NSEvent) { scheduleHide(after: 0.25) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    /// Fade the pill in and (re)arm the auto-hide; also called from the panel's top-edge hover funnel.
    func reveal() {
        hideTimer?.invalidate()
        if pill.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                pill.animator().alphaValue = 1
            }
        }
        scheduleHide(after: 1.5)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideNow() }
        }
    }

    private func hideNow() {
        hideTimer?.invalidate()
        hideTimer = nil
        guard dragStart == nil else { return }
        // Never fade under a pointer resting on the strip — a resting pointer never re-fires `mouseEntered`, and a grab at a just-faded pill would fall through to the desktop behind and dismiss the palette.
        if let window, NSMouseInRect(NSEvent.mouseLocation, screenStripRect(of: window), false) {
            scheduleHide(after: 1.5)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            pill.animator().alphaValue = 0
        }
    }

    private func screenStripRect(of window: NSWindow) -> NSRect {
        NSRect(
            x: window.frame.minX, y: window.frame.maxY - Self.stripHeight,
            width: window.frame.width, height: Self.stripHeight)
    }

    // Only the pill's drawn pixels are reachable — the rest of the strip is click-through at the window server.
    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, !didDrag else { return }
        let now = NSEvent.mouseLocation
        guard hypot(now.x - start.x, now.y - start.y) > Self.clickSlop else { return }
        didDrag = true
        // Hand the rest of the gesture to the window server: the native drag, fed this event's own window and coordinates, is exactly what `isMovableByWindowBackground` would have done.
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = didDrag
        dragStart = nil
        didDrag = false
        scheduleHide(after: 0.8)
        if !wasDrag { onClick?() }
    }
}

/// The grab pill itself: a small capsule chip, legible over any wallpaper in either appearance,
/// built from semantic colors so the system flips both stops together.
private final class PalettePillView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let chip = NSRect(x: bounds.midX - 32, y: bounds.midY - 6, width: 64, height: 12)
        let chipPath = NSBezierPath(roundedRect: chip, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        chipPath.fill()
        NSColor.separatorColor.setStroke()
        chipPath.lineWidth = 1
        chipPath.stroke()
        let bar = NSRect(x: bounds.midX - 18, y: bounds.midY - 2.5, width: 36, height: 5)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
    }
}
