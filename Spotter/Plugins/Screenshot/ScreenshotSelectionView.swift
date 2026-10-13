import AppKit

/// One selection session, three outputs: Space cycles what a capture produces. Screenshot mode is
/// where every session starts — a left drag selects a region, a right click captures the window
/// under the pointer, and Tab captures the whole display.
enum ScreenshotCaptureMode: CaseIterable {
    case screenshot
    /// Drag a region and keep only the text inside it.
    case ocr
    /// Click a pixel and copy its hex value.
    case colorPicker

    var next: ScreenshotCaptureMode {
        switch self {
        case .screenshot: .ocr
        case .ocr: .colorPicker
        case .colorPicker: .screenshot
        }
    }

    /// Whether the user draws an area, as opposed to clicking a single point.
    var isDragSelection: Bool { self == .screenshot || self == .ocr }
}

enum ScreenshotSelectionKey: Int, CaseIterable {
    case escape = 53
    case space = 49
    case tab = 48

    var id: String { "screenshot.selection.\(rawValue)" }
}

// A key nonactivating panel still steals keyboard focus and disrupts an open menu on modifier changes.
final class ScreenshotSelectionPanel: NSPanel {
    private let selectionView: ScreenshotSelectionView

    init(screenFrame: CGRect, contentView: ScreenshotSelectionView) {
        selectionView = contentView
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .screenSaver
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        self.contentView = contentView

        let preventsActivation = NSSelectorFromString("_setPreventsActivation:")
        if responds(to: preventsActivation) {
            perform(preventsActivation, with: NSNumber(value: true))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func activate() {
        orderFrontRegardless()
    }

    func prepareForPresentation() {
        selectionView.prepareForPresentation()
    }

    func apply(mode: ScreenshotCaptureMode) {
        selectionView.apply(mode: mode)
    }

    func captureScreenIfIdle() {
        selectionView.captureScreenIfIdle()
    }

    func handlePointer(_ type: CGEventType, at globalPoint: CGPoint) {
        selectionView.handlePointer(type, at: CGPoint(x: globalPoint.x - frame.minX, y: globalPoint.y - frame.minY))
    }

    func deactivate() {
        orderOut(nil)
    }
}

final class ScreenshotSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onColorPick: ((CGPoint) -> Void)?
    var onWindowCapture: (() -> Void)?
    var onScreenCapture: (() -> Void)?
    var onCancel: (() -> Void)?

    private let roundedCorners: Bool
    private let screenFrame: CGRect
    private var mode: ScreenshotCaptureMode = .screenshot
    private var cursor: NSCursor { ScreenshotCursor.cursor(for: mode) }
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private static let selectionStrokeWidthPixels: CGFloat = 1

    init(screenFrame: CGRect, visibleFrame: CGRect, roundedCorners: Bool) {
        self.roundedCorners = roundedCorners
        self.screenFrame = screenFrame
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [
                .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect,
            ],
            owner: self,
            userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        setPointerCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        setPointerCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        setPointerCursor()
    }

    func prepareForPresentation() {
        refreshCursorRects()
    }

    func apply(mode: ScreenshotCaptureMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        dragStart = nil
        selection = nil
        refreshCursorRects()
        needsDisplay = true
    }

    private func setPointerCursor() {
        cursor.set()
    }

    private func localPointerLocation() -> CGPoint {
        CGPoint(
            x: NSEvent.mouseLocation.x - screenFrame.minX,
            y: NSEvent.mouseLocation.y - screenFrame.minY)
    }

    /// Rebuilding the cursor rects is what stops a later pointer move from restoring the previous
    /// symbol — but AppKit drops the live pointer back to the arrow while it rebuilds, and only
    /// re-applies a rect's cursor once the pointer moves into it. A stationary pointer would sit on
    /// the arrow until the user twitched the mouse, so the cursor is set again after the rebuild has
    /// been processed as well as before it.
    private func refreshCursorRects() {
        window?.invalidateCursorRects(for: self)
        setCursorIfPointerInside()
        DispatchQueue.main.async { [weak self] in self?.setCursorIfPointerInside() }
    }

    /// NSMouseInRect, not `contains`: on the top edge the pointer's y sits exactly on `frame.maxY`,
    /// which a plain rect-contains misses.
    private func setCursorIfPointerInside() {
        guard let window, NSMouseInRect(NSEvent.mouseLocation, window.frame, false) else { return }
        setPointerCursor()
    }

    override func mouseDown(with event: NSEvent) {
        handlePointer(.leftMouseDown, at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointer(.leftMouseDragged, at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        handlePointer(.leftMouseUp, at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseUp(with event: NSEvent) {
        handlePointer(.rightMouseUp, at: convert(event.locationInWindow, from: nil))
    }

    func handlePointer(_ type: CGEventType, at location: CGPoint) {
        let point = ScreenshotGeometry.clampedPoint(location, to: bounds)
        cursor.set()
        switch type {
        case .leftMouseDown:
            guard mode.isDragSelection else { return }
            dragStart = point
            selection = .zero
            needsDisplay = true
        case .leftMouseDragged:
            guard mode.isDragSelection, let dragStart else { return }
            selection = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
            needsDisplay = true
        case .leftMouseUp:
            if mode == .colorPicker { onColorPick?(point); return }
            guard let dragStart else { return }
            let rect = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
            self.dragStart = nil
            selection = nil
            if ScreenshotGeometry.isCapturable(rect) { onSelection?(rect) } else { onCancel?() }
        case .rightMouseUp:
            guard mode == .screenshot, dragStart == nil else { return }
            onWindowCapture?()
        default: break
        }
    }

    func captureScreenIfIdle() {
        guard mode == .screenshot, dragStart == nil else { return }
        onScreenCapture?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHitSurface()
        if let selection, ScreenshotGeometry.isCapturable(selection) {
            drawSelection(selection)
        }
    }

    private func drawHitSurface() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(NSColor(Theme.Colors.screenshotHitSurface).cgColor)
        context.fill(bounds)
        context.restoreGState()
    }

    private func drawSelection(_ selection: CGRect) {
        let scale = max(window?.backingScaleFactor ?? 1, 1)
        let strokeWidth = Self.selectionStrokeWidthPixels / scale
        let borderRect = selection.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let radius = roundedCorners
            ? ScreenshotGeometry.roundedCornerRadius(
                forPixelSize: CGSize(
                    width: selection.width * scale, height: selection.height * scale)) / scale
            : 0
        let fillPath = CGPath(
            roundedRect: selection,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor(NSColor(Theme.Colors.screenshotSelectionOverlay).cgColor)
        context.addPath(fillPath)
        context.fillPath()
        context.restoreGState()

        let border = radius > 0
            ? NSBezierPath(roundedRect: borderRect, xRadius: radius, yRadius: radius)
            : NSBezierPath(rect: borderRect)
        border.lineWidth = strokeWidth
        NSColor(Theme.Colors.screenshotSelectionBorder).setStroke()
        border.stroke()
    }
}

