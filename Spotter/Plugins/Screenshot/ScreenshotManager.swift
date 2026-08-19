import AppKit
import Combine
import ScreenCaptureKit

enum ScreenshotCaptureResult {
    case copied
    case cancelled
    case permissionRequired
    case failed
}

private enum ScreenshotCaptureFailure: LocalizedError {
    case displayUnavailable

    var errorDescription: String? { "The selected display is no longer available." }
}

/// Owns the short-lived selection panels and the one-shot ScreenCaptureKit request.
@MainActor
final class ScreenshotManager: ObservableObject {
    private static let roundedCornersKey = "screenshot.rounded-corners"

    private var panels: [ScreenshotSelectionPanel] = []
    private var completion: ((ScreenshotCaptureResult) -> Void)?
    private var captureTask: Task<Void, Never>?
    private var isSystemCursorHidden = false
    private let defaults: UserDefaults

    @Published var roundedCorners: Bool {
        didSet {
            guard roundedCorners != oldValue else { return }
            defaults.set(roundedCorners, forKey: Self.roundedCornersKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        roundedCorners = defaults.object(forKey: Self.roundedCornersKey) == nil
            || defaults.bool(forKey: Self.roundedCornersKey)
    }

    var isCapturing: Bool { !panels.isEmpty || captureTask != nil }

    func begin(completion: @escaping (ScreenshotCaptureResult) -> Void) {
        cancel(notifying: false)
        let alreadyAllowed = Permissions.isScreenRecordingAllowed()
        AppLog.info("screenshot", "Beginning capture; screen recording allowed: \(alreadyAllowed).")
        if !alreadyAllowed {
            let granted = Permissions.requestScreenRecording()
            guard granted || Permissions.isScreenRecordingAllowed() else {
                AppLog.info("screenshot", "Capture stopped because Screen Recording access is unavailable.")
                completion(.permissionRequired)
                return
            }
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(.failed)
            return
        }

        self.completion = completion
        panels = screens.map(makePanel)

        for panel in panels { panel.activate() }
        hideSystemCursor()
        for panel in panels { panel.prepareForPresentation() }

        let frames = panels.map { NSStringFromRect($0.frame) }.joined(separator: ", ")
        AppLog.info("screenshot", "Selection is active across \(panels.count) display(s): \(frames).")
    }

    func cancel() {
        cancel(notifying: true)
    }

    private func makePanel(for screen: NSScreen) -> ScreenshotSelectionPanel {
        let view = ScreenshotSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            roundedCorners: roundedCorners)
        let panel = ScreenshotSelectionPanel(screen: screen, contentView: view)
        view.onSelection = { [weak self, weak screen] localRect in
            guard let self, let screen else { return }
            finishSelection(localRect, on: screen)
        }
        view.onCancel = { [weak self] in self?.cancel() }
        return panel
    }

    private func finishSelection(_ localRect: CGRect, on screen: NSScreen) {
        guard ScreenshotGeometry.isCapturable(localRect), let displayID = screen.displayID else {
            cancel()
            return
        }
        let captureRect = ScreenshotGeometry.captureRect(
            fromScreenLocal: localRect, screenHeight: screen.frame.height)
        dismissPanels()

        captureTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                let image = try await Self.captureImage(in: captureRect, displayID: displayID)
                guard !Task.isCancelled else { return }
                let roundedCorners = self.roundedCorners
                let tiff = await Task.detached(priority: .userInitiated) {
                    ScreenshotImageProcessor.tiffData(
                        from: image, roundedCorners: roundedCorners)
                }.value
                guard !Task.isCancelled, let tiff, writeToPasteboard(tiff) else {
                    captureTask = nil
                    finish(.failed)
                    return
                }
                captureTask = nil
                finish(.copied)
            } catch {
                AppLog.error("screenshot", "ScreenCaptureKit failed: \(error.localizedDescription)")
                captureTask = nil
                finish(.failed)
            }
        }
    }

    private static func captureImage(
        in rect: CGRect, displayID: CGDirectDisplayID
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotCaptureFailure.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.sourceRect = rect
        configuration.width = max(Int((rect.width * scale).rounded()), 1)
        configuration.height = max(Int((rect.height * scale).rounded()), 1)
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
    }

    private func writeToPasteboard(_ tiff: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.tiff, ClipboardManager.internalType], owner: nil)
        pasteboard.setData(tiff, forType: .tiff)
        pasteboard.setData(Data(), forType: ClipboardManager.internalType)
        return true
    }

    private func cancel(notifying: Bool) {
        let hadWork = isCapturing
        captureTask?.cancel()
        captureTask = nil
        dismissPanels()
        if notifying, hadWork { finish(.cancelled) }
        if !notifying { completion = nil }
    }

    private func dismissPanels() {
        for panel in panels { panel.deactivate() }
        panels = []
        restoreSystemCursor()
    }

    private func hideSystemCursor() {
        guard !isSystemCursorHidden else { return }
        NSCursor.hide()
        isSystemCursorHidden = true
    }

    private func restoreSystemCursor() {
        guard isSystemCursorHidden else { return }
        NSCursor.unhide()
        isSystemCursorHidden = false
    }

    private func finish(_ result: ScreenshotCaptureResult) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

private final class ScreenshotSelectionPanel: NSPanel {
    private let selectionView: ScreenshotSelectionView

    init(screen: NSScreen, contentView: ScreenshotSelectionView) {
        selectionView = contentView
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        level = .screenSaver
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        self.contentView = contentView

        let preventsActivation = NSSelectorFromString("_setPreventsActivation:")
        if responds(to: preventsActivation) {
            perform(preventsActivation, with: NSNumber(value: true))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func activate() {
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(selectionView)
    }

    func prepareForPresentation() {
        selectionView.prepareForPresentation()
    }

    func deactivate() {
        orderOut(nil)
    }
}

private final class ScreenshotSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let roundedCorners: Bool
    private var dragStart: CGPoint?
    private var pointerLocation: CGPoint?
    private var selection: CGRect?
    private static let selectionStrokeWidthPixels: CGFloat = 1

    init(frame: NSRect, roundedCorners: Bool) {
        self.roundedCorners = roundedCorners
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func prepareForPresentation() {
        guard let window else { return }
        let screenLocation = NSEvent.mouseLocation
        guard window.frame.contains(screenLocation) else {
            pointerLocation = nil
            return
        }
        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        pointerLocation = ScreenshotGeometry.clampedPoint(convert(windowPoint, from: nil), to: bounds)
        needsDisplay = true
        displayIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            onCancel?()
            return
        }
        window?.makeKey()
        window?.makeFirstResponder(self)
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        dragStart = point
        pointerLocation = point
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        pointerLocation = point
        selection = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0, let dragStart else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        let rect = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
        self.dragStart = nil
        pointerLocation = point
        selection = nil
        if ScreenshotGeometry.isCapturable(rect) {
            onSelection?(rect)
        } else {
            onCancel?()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        guard dragStart == nil else { return }
        pointerLocation = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func updatePointer(with event: NSEvent) {
        pointerLocation = ScreenshotGeometry.clampedPoint(
            convert(event.locationInWindow, from: nil), to: bounds)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHitSurface()
        if let selection, ScreenshotGeometry.isCapturable(selection) {
            drawSelection(selection)
        }
        if let pointerLocation { drawReticle(at: pointerLocation) }
    }

    private func drawHitSurface() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
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

    private func drawReticle(at point: CGPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let armLength: CGFloat = 12
        let gap: CGFloat = 3
        let arms = [
            (CGPoint(x: point.x, y: point.y + gap), CGPoint(x: point.x, y: point.y + gap + armLength)),
            (CGPoint(x: point.x, y: point.y - gap), CGPoint(x: point.x, y: point.y - gap - armLength)),
            (CGPoint(x: point.x + gap, y: point.y), CGPoint(x: point.x + gap + armLength, y: point.y)),
            (CGPoint(x: point.x - gap, y: point.y), CGPoint(x: point.x - gap - armLength, y: point.y)),
        ]
        stroke(arms, in: context, color: NSColor(Theme.Colors.screenshotReticleOuter), width: 3)
        stroke(arms, in: context, color: NSColor(Theme.Colors.screenshotReticleInner), width: 1)
    }

    private func stroke(
        _ arms: [(CGPoint, CGPoint)], in context: CGContext, color: NSColor, width: CGFloat
    ) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        for (start, end) in arms {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
