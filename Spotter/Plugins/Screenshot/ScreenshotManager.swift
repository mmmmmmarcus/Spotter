import AppKit
import Carbon.HIToolbox
import Combine
import ScreenCaptureKit

enum ScreenshotCaptureResult {
    case copied
    case cancelled
    case permissionRequired
    case failed
}

/// What the editor needs from the most recent capture: the raw pixels plus the corner treatment
/// the clipboard copy already received, so an edited re-copy matches the original.
struct ScreenshotCapturePayload: Sendable {
    let image: CGImage
    let roundedCorners: Bool
}

/// Region selection is where every capture starts; Space cycles on through whole-window and
/// whole-display picking and back around.
enum ScreenshotCaptureMode: CaseIterable {
    case region
    case window
    case screen

    var next: ScreenshotCaptureMode {
        switch self {
        case .region: .window
        case .window: .screen
        case .screen: .region
        }
    }
}

private enum ScreenshotCaptureFailure: LocalizedError {
    case displayUnavailable
    case windowUnavailable

    var errorDescription: String? {
        switch self {
        case .displayUnavailable: "The selected display is no longer available."
        case .windowUnavailable: "The selected window is no longer available."
        }
    }
}

/// Owns the short-lived selection panels and the one-shot ScreenCaptureKit request.
@MainActor
final class ScreenshotManager: ObservableObject {
    private static let roundedCornersKey = "screenshot.rounded-corners"
    private static let captureScaleKey = "screenshot.capture-scale"
    private static let fileFormatKey = "screenshot.file-format"
    private static let includesWindowShadowKey = "screenshot.includes-window-shadow"
    private static let hidesSpotterWindowsKey = "screenshot.hides-spotter-windows"

    private var panels: [ScreenshotSelectionPanel] = []
    private var completion: ((ScreenshotCaptureResult) -> Void)?
    private var captureTask: Task<Void, Never>?
    private var previousCursor: NSCursor?
    private var mode: ScreenshotCaptureMode = .region
    private var hoveredWindow: ScreenshotWindowCandidate?
    /// Retained until the next capture so the thumbnail can open the editor after the panels are gone.
    private(set) var lastCapture: ScreenshotCapturePayload?
    /// The post-capture thumbnail. Created with the app's hotkey manager because Return reaches it
    /// through a transient system key rather than the responder chain.
    let preview: ScreenshotPreviewHUD
    /// Every torn-off capture still floating on screen; each closes itself and drops out of here.
    private var pins: [ScreenshotPinWindow] = []
    private let cursorAnimator = ScreenshotCursorAnimator()
    private unowned let hotKeys: HotKeyManager
    private let defaults: UserDefaults
    private static let escapeKeyID = "screenshot.selection.escape"

    @Published var roundedCorners: Bool {
        didSet {
            guard roundedCorners != oldValue else { return }
            defaults.set(roundedCorners, forKey: Self.roundedCornersKey)
        }
    }

    @Published var captureScale: ScreenshotCaptureScale {
        didSet {
            guard captureScale != oldValue else { return }
            defaults.set(captureScale.rawValue, forKey: Self.captureScaleKey)
        }
    }

    @Published var fileFormat: ScreenshotFileFormat {
        didSet {
            guard fileFormat != oldValue else { return }
            defaults.set(fileFormat.rawValue, forKey: Self.fileFormatKey)
        }
    }

    /// Window mode only; a region drag has no shadow to include.
    @Published var includesWindowShadow: Bool {
        didSet {
            guard includesWindowShadow != oldValue else { return }
            defaults.set(includesWindowShadow, forKey: Self.includesWindowShadowKey)
        }
    }

    /// Off by default: closing the user's open windows is a bigger side effect than a capture
    /// normally has, so it stays something they ask for.
    @Published var hidesSpotterWindows: Bool {
        didSet {
            guard hidesSpotterWindows != oldValue else { return }
            defaults.set(hidesSpotterWindows, forKey: Self.hidesSpotterWindowsKey)
        }
    }

    init(hotKeys: HotKeyManager, defaults: UserDefaults = .standard) {
        self.hotKeys = hotKeys
        preview = ScreenshotPreviewHUD(hotKeys: hotKeys)
        self.defaults = defaults
        roundedCorners = defaults.object(forKey: Self.roundedCornersKey) == nil
            || defaults.bool(forKey: Self.roundedCornersKey)
        captureScale = defaults.string(forKey: Self.captureScaleKey)
            .flatMap(ScreenshotCaptureScale.init(rawValue:)) ?? .retina
        fileFormat = defaults.string(forKey: Self.fileFormatKey)
            .flatMap(ScreenshotFileFormat.init(rawValue:)) ?? .png
        includesWindowShadow = defaults.bool(forKey: Self.includesWindowShadowKey)
        hidesSpotterWindows = defaults.bool(forKey: Self.hidesSpotterWindowsKey)
        cursorAnimator.onFrame = { [weak self] cursor in
            guard let self else { return }
            for panel in panels { panel.apply(cursor: cursor) }
        }
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
        mode = .region
        hoveredWindow = nil
        cursorAnimator.reset(to: mode)
        previousCursor = NSCursor.current
        BackgroundCursor.setAllowed(true)
        panels = screens.map(makePanel)

        for panel in panels { panel.activate() }
        for panel in panels { panel.prepareForPresentation() }
        // The view's own keyDown only fires when the overlay actually holds keyboard focus, which
        // depends on what was frontmost when the shortcut fired. Escape is the one key that must
        // always work, so it is claimed system-wide for the life of the selection and released
        // with the panels.
        hotKeys.holdTransientKey(
            id: Self.escapeKeyID,
            shortcut: KeyShortcut(carbonKeyCode: kVK_Escape, carbonModifiers: 0)
        ) { [weak self] in
            self?.cancel()
        }

        let frames = panels.map { NSStringFromRect($0.frame) }.joined(separator: ", ")
        AppLog.info("screenshot", "Selection is active across \(panels.count) display(s): \(frames).")
    }

    func cancel() {
        cancel(notifying: true)
    }

    /// Disabling the plugin drops the retained capture along with the editor that shows it.
    func clearLastCapture() {
        preview.dismiss()
        closeAllPins()
        lastCapture = nil
    }

    /// Floats a capture above every app. `onOpen` is wired by the plugin, which owns the editor.
    @discardableResult
    func pin(
        _ capture: ScreenshotCapturePayload, thumbnail: CGSize, at point: CGPoint,
        onOpen: @escaping (ScreenshotCapturePayload) -> Void
    ) -> ScreenshotPinWindow {
        let pin = ScreenshotPinWindow(capture: capture)
        pin.onOpen = onOpen
        pin.onClose = { [weak self] closed in
            self?.pins.removeAll { $0 === closed }
        }
        pins.append(pin)
        pin.present(from: thumbnail, at: point)
        AppLog.info("screenshot", "Pinned a capture; \(pins.count) pin(s) on screen.")
        return pin
    }

    func closeAllPins() {
        for pin in pins { pin.close() }
        pins = []
    }

    private func makePanel(for screen: NSScreen) -> ScreenshotSelectionPanel {
        let view = ScreenshotSelectionView(
            screenFrame: screen.frame,
            roundedCorners: roundedCorners)
        let panel = ScreenshotSelectionPanel(screen: screen, contentView: view)
        view.onSelection = { [weak self, weak screen] localRect in
            guard let self, let screen else { return }
            finishSelection(localRect, on: screen)
        }
        view.onWindowSelection = { [weak self] in self?.capturePickedTarget() }
        view.onToggleMode = { [weak self] in self?.toggleMode() }
        view.onPointerMoved = { [weak self] in self?.refreshHoveredWindow() }
        view.onCancel = { [weak self] in self?.cancel() }
        return panel
    }

    private func toggleMode() {
        mode = mode.next
        AppLog.info("screenshot", "Capture mode is now \(mode).")
        for panel in panels { panel.apply(mode: mode) }
        cursorAnimator.transition(to: mode)
        refreshHoveredWindow()
    }

    /// Window and screen modes highlight whatever sits under the pointer, so this reruns on every pointer move.
    private func refreshHoveredWindow() {
        if mode == .screen {
            hoveredWindow = nil
            applyHighlight(Self.screenUnderPointer()?.frame)
            return
        }
        guard mode == .window else {
            guard hoveredWindow != nil else { return }
            hoveredWindow = nil
            applyHighlight(nil)
            return
        }
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let point = ScreenshotWindowPicker.displaySpacePoint(
            fromAppKit: NSEvent.mouseLocation, primaryScreenMaxY: primaryScreenMaxY)
        let target = ScreenshotWindowPicker.target(
            at: point,
            in: Self.windowCandidates(),
            excluding: ProcessInfo.processInfo.processIdentifier)
        guard target != hoveredWindow else { return }
        hoveredWindow = target
        applyHighlight(
            target.map {
                ScreenshotWindowPicker.appKitRect(
                    fromDisplaySpace: $0.bounds, primaryScreenMaxY: primaryScreenMaxY)
            })
    }

    /// NSMouseInRect, not `contains`: on the top edge the pointer's y sits on `frame.maxY`.
    private static func screenUnderPointer() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }

    private func applyHighlight(_ globalRect: CGRect?) {
        for panel in panels { panel.apply(highlight: globalRect) }
    }

    private static func windowCandidates() -> [ScreenshotWindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard
                let id = entry[kCGWindowNumber as String] as? Int,
                let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsEntry = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsEntry as CFDictionary)
            else { return nil }
            return ScreenshotWindowCandidate(
                id: CGWindowID(id),
                ownerPID: Int32(ownerPID),
                layer: layer,
                alpha: entry[kCGWindowAlpha as String] as? CGFloat ?? 1,
                bounds: bounds)
        }
    }

    private func finishSelection(_ localRect: CGRect, on screen: NSScreen) {
        guard ScreenshotGeometry.isCapturable(localRect), let displayID = screen.displayID else {
            cancel()
            return
        }
        let captureRect = ScreenshotGeometry.captureRect(
            fromScreenLocal: localRect, screenHeight: screen.frame.height)
        let roundedCorners = roundedCorners
        let captureScale = captureScale
        dismissPanels()

        captureTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                let image = try await Self.captureImage(
                    in: captureRect, displayID: displayID, scale: captureScale)
                await deliver(image, roundedCorners: roundedCorners)
            } catch {
                AppLog.error("screenshot", "ScreenCaptureKit failed: \(error.localizedDescription)")
                captureTask = nil
                finish(.failed)
            }
        }
    }

    private func capturePickedTarget() {
        if mode == .screen {
            captureHoveredScreen()
        } else {
            captureHoveredWindow()
        }
    }

    /// The whole display under the pointer, captured through the same display path a region uses —
    /// the source rectangle is simply the display's full bounds.
    private func captureHoveredScreen() {
        guard let screen = Self.screenUnderPointer(), let displayID = screen.displayID else {
            cancel()
            return
        }
        let captureRect = CGRect(origin: .zero, size: screen.frame.size)
        let captureScale = captureScale
        dismissPanels()

        captureTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                let image = try await Self.captureImage(
                    in: captureRect, displayID: displayID, scale: captureScale)
                // A whole display has no corners to round; the desktop fills every pixel.
                await deliver(image, roundedCorners: false)
            } catch {
                AppLog.error("screenshot", "Screen capture failed: \(error.localizedDescription)")
                captureTask = nil
                finish(.failed)
            }
        }
    }

    /// A window image already carries its own rounded alpha corners, so it skips the corner pass.
    private func captureHoveredWindow() {
        refreshHoveredWindow()
        guard let target = hoveredWindow else {
            cancel()
            return
        }
        let captureScale = captureScale
        let includesWindowShadow = includesWindowShadow
        dismissPanels()

        captureTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                let image = try await Self.captureImage(
                    windowID: target.id, scale: captureScale,
                    includingShadow: includesWindowShadow)
                await deliver(image, roundedCorners: false)
            } catch {
                AppLog.error("screenshot", "Window capture failed: \(error.localizedDescription)")
                captureTask = nil
                finish(.failed)
            }
        }
    }

    private func deliver(_ image: CGImage, roundedCorners: Bool) async {
        let tiff = await Task.detached(priority: .userInitiated) {
            ScreenshotImageProcessor.tiffData(from: image, roundedCorners: roundedCorners)
        }.value
        guard !Task.isCancelled, let tiff, writeToPasteboard(tiff) else {
            captureTask = nil
            finish(.failed)
            return
        }
        lastCapture = ScreenshotCapturePayload(image: image, roundedCorners: roundedCorners)
        captureTask = nil
        finish(.copied)
    }

    /// Reuses the capture pipeline's processing and internal-type marker for an edited image.
    func copyEdited(_ image: CGImage, roundedCorners: Bool) async -> Bool {
        let tiff = await Task.detached(priority: .userInitiated) {
            ScreenshotImageProcessor.tiffData(from: image, roundedCorners: roundedCorners)
        }.value
        guard let tiff else { return false }
        return writeToPasteboard(tiff)
    }

    private static func captureImage(
        in rect: CGRect, displayID: CGDirectDisplayID, scale: ScreenshotCaptureScale
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotCaptureFailure.displayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let pixels = scale.pixelSize(
            forPointSize: rect.size, nativeScale: CGFloat(filter.pointPixelScale))
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.sourceRect = rect
        configuration.width = pixels.width
        configuration.height = pixels.height
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
    }

    private static func captureImage(
        windowID: CGWindowID, scale: ScreenshotCaptureScale, includingShadow: Bool
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenshotCaptureFailure.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        // `contentRect` already reserves the shadow margin, so only the ignore flag decides whether it is drawn or cropped away.
        let pixels = scale.pixelSize(
            forPointSize: filter.contentRect.size,
            nativeScale: CGFloat(filter.pointPixelScale))
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = !includingShadow
        configuration.width = pixels.width
        configuration.height = pixels.height
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
        hotKeys.releaseTransientKey(id: Self.escapeKeyID)
        cursorAnimator.stop()
        for panel in panels { panel.deactivate() }
        panels = []
        hoveredWindow = nil
        previousCursor?.set()
        previousCursor = nil
        BackgroundCursor.setAllowed(false)
    }

    private func finish(_ result: ScreenshotCaptureResult) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

/// The window server drops cursor changes from a background app, so the crosshair would only take
/// hold once a drag grabbed the pointer. Capso's connection property lifts that for the session.
private enum BackgroundCursor {
    private typealias MainConnectionID = @convention(c) () -> UInt32
    private typealias SetConnectionProperty =
        @convention(c) (UInt32, UInt32, CFString, CFTypeRef) -> Int32

    static func setAllowed(_ allowed: Bool) {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return }
        defer { dlclose(handle) }
        guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
            let propertySymbol = dlsym(handle, "CGSSetConnectionProperty")
        else {
            AppLog.info("screenshot", "Background cursor updates are unavailable on this system.")
            return
        }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnectionID.self)()
        _ = unsafeBitCast(propertySymbol, to: SetConnectionProperty.self)(
            connection, connection, "SetsCursorInBackground" as CFString,
            allowed ? kCFBooleanTrue as CFTypeRef : kCFBooleanFalse as CFTypeRef)
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

    func apply(cursor: NSCursor) {
        selectionView.apply(cursor: cursor)
    }

    func apply(mode: ScreenshotCaptureMode) {
        selectionView.apply(mode: mode)
    }

    func apply(highlight: CGRect?) {
        selectionView.apply(highlight: highlight)
    }

    func deactivate() {
        orderOut(nil)
    }
}

private final class ScreenshotSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onWindowSelection: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var onPointerMoved: (() -> Void)?
    var onCancel: (() -> Void)?

    private let roundedCorners: Bool
    private let screenFrame: CGRect
    private var mode: ScreenshotCaptureMode = .region
    private var cursor: NSCursor = ScreenshotCursor.region
    private var highlight: CGRect?
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private static let selectionStrokeWidthPixels: CGFloat = 1

    init(screenFrame: CGRect, roundedCorners: Bool) {
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

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
        onPointerMoved?()
    }

    override func mouseEntered(with event: NSEvent) {
        cursor.set()
        onPointerMoved?()
    }

    func prepareForPresentation() {
        guard let window else { return }
        window.invalidateCursorRects(for: self)
        guard window.frame.contains(NSEvent.mouseLocation) else { return }
        cursor.set()
    }

    func apply(mode: ScreenshotCaptureMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        dragStart = nil
        selection = nil
        needsDisplay = true
    }

    /// Each transition frame arrives here; the cursor rect is rebuilt with it so a pointer move mid-swap cannot restore the previous pointer.
    func apply(cursor: NSCursor) {
        self.cursor = cursor
        window?.invalidateCursorRects(for: self)
        if window?.frame.contains(NSEvent.mouseLocation) == true { cursor.set() }
    }

    func apply(highlight rect: CGRect?) {
        let local = rect.map { $0.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }
        guard local != highlight else { return }
        highlight = local
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else {
            onCancel?()
            return
        }
        window?.makeKey()
        window?.makeFirstResponder(self)
        cursor.set()
        guard mode == .region else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        dragStart = point
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .region, let dragStart else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        selection = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
        cursor.set()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        guard mode == .region else {
            onWindowSelection?()
            return
        }
        guard let dragStart else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        let rect = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
        self.dragStart = nil
        selection = nil
        if ScreenshotGeometry.isCapturable(rect) {
            onSelection?(rect)
        } else {
            onCancel?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 49:
            onToggleMode?()
        default:
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHitSurface()
        if mode != .region {
            if let highlight, ScreenshotGeometry.isCapturable(highlight) {
                drawSelection(highlight)
            }
        } else if let selection, ScreenshotGeometry.isCapturable(selection) {
            drawSelection(selection)
        }
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
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
