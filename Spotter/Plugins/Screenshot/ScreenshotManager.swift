import AppKit
import Carbon.HIToolbox
import Combine
import ScreenCaptureKit

enum ScreenshotCaptureResult {
    case copied
    case textCopied
    case colorCopied(String)
    case noTextFound
    case cancelled
    case permissionRequired
    case failed
}

/// What the editor needs from the most recent capture: the raw pixels plus the corner treatment
/// the clipboard copy already received, so an edited re-copy matches the original.
struct ScreenshotCapturePayload: Sendable {
    let image: CGImage
    let roundedCorners: Bool
    /// The app that was frontmost when the capture started, which is what the capture is *of* as
    /// far as the user is concerned — it names the file and attributes the history entry.
    let sourceAppName: String?
    let sourceBundleID: String?
    let capturedAt: Date

    init(
        image: CGImage, roundedCorners: Bool, sourceAppName: String? = nil,
        sourceBundleID: String? = nil, capturedAt: Date = Date()
    ) {
        self.image = image
        self.roundedCorners = roundedCorners
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.capturedAt = capturedAt
    }

    /// Without an extension: the editor's Save adds the one the chosen format wants.
    var fileName: String {
        ScreenshotFileName.name(forApp: sourceAppName, at: capturedAt)
    }
}

/// One selection session, three outputs: Space cycles what a capture produces. Screenshot mode is
/// where every session starts — a left drag selects a region, a right click captures the window
/// under the pointer, and each display's glass button captures that whole screen.
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
    private static let previewDurationKey = "screenshot.preview-duration"

    private var panels: [ScreenshotSelectionPanel] = []
    private var completion: ((ScreenshotCaptureResult) -> Void)?
    private var captureTask: Task<Void, Never>?
    private var previousCursor: NSCursor?
    private var mode: ScreenshotCaptureMode = .screenshot
    private var selectionStartedAt: Date?
    /// Recorded when the selection opens, before any overlay can take the frontmost app's place.
    private var captureSource: (name: String?, bundleID: String?)?
    /// Retained until the next capture so the thumbnail can open the editor after the panels are gone.
    private(set) var lastCapture: ScreenshotCapturePayload?
    /// Where on screen the last capture came from, so its thumbnail can drift in from that
    /// direction. Global AppKit coordinates.
    private(set) var lastCaptureRect: CGRect?
    /// Every thumbnail still on screen, oldest first. Captures taken in quick succession sit side
    /// by side rather than replacing one another.
    private var previews: [ScreenshotPreviewHUD] = []
    /// The screen the row is laid out on, fixed while the row is non-empty so an arriving thumbnail
    /// cannot drag the others onto whichever display the pointer happens to be over.
    private var previewScreen: NSScreen?
    /// Gap between neighbouring thumbnails in the row.
    private static let previewGap: CGFloat = 12
    private static let previewReturnKeyID = "screenshot.preview.return"
    /// Ends the Return claim on its own if the user neither clicks away nor uses it.
    private var returnGrace: Task<Void, Never>?
    /// Passive mouse-down monitor, alive only while Return is claimed.
    private var returnHandback: Any?
    /// Every torn-off capture still floating on screen; each closes itself and drops out of here.
    private var pins: [ScreenshotPinWindow] = []
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

    /// How long a thumbnail stays up before it dismisses itself. Applies to thumbnails already on
    /// screen through the row's shared countdown, so a change is visible on the next capture.
    @Published var previewDuration: Double {
        didSet {
            let clamped = Self.clampPreviewDuration(previewDuration)
            guard clamped == previewDuration else {
                previewDuration = clamped
                return
            }
            guard previewDuration != oldValue else { return }
            defaults.set(previewDuration, forKey: Self.previewDurationKey)
        }
    }

    static let previewDurationRange: ClosedRange<Double> = 1...60
    static let defaultPreviewDuration: Double = 3.5

    static func clampPreviewDuration(_ value: Double) -> Double {
        min(max(value, previewDurationRange.lowerBound), previewDurationRange.upperBound)
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
        self.defaults = defaults
        roundedCorners = defaults.object(forKey: Self.roundedCornersKey) == nil
            || defaults.bool(forKey: Self.roundedCornersKey)
        captureScale = defaults.string(forKey: Self.captureScaleKey)
            .flatMap(ScreenshotCaptureScale.init(rawValue:)) ?? .retina
        fileFormat = defaults.string(forKey: Self.fileFormatKey)
            .flatMap(ScreenshotFileFormat.init(rawValue:)) ?? .png
        includesWindowShadow = defaults.bool(forKey: Self.includesWindowShadowKey)
        hidesSpotterWindows = defaults.bool(forKey: Self.hidesSpotterWindowsKey)
        previewDuration = defaults.object(forKey: Self.previewDurationKey) == nil
            ? Self.defaultPreviewDuration
            : Self.clampPreviewDuration(defaults.double(forKey: Self.previewDurationKey))
    }

    var isCapturing: Bool { !panels.isEmpty || captureTask != nil }

    /// A second shortcut press means "get me out of here" once the selection has been up long
    /// enough to see. Presses inside that window are key repeat, which must not tear the panels
    /// down and rebuild them under the pointer.
    var acceptsShortcutCancel: Bool {
        guard let startedAt = selectionStartedAt else { return false }
        return Date().timeIntervalSince(startedAt) >= 0.4
    }

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
        let frontmost = NSWorkspace.shared.frontmostApplication
        captureSource = (frontmost?.localizedName, frontmost?.bundleIdentifier)
        mode = .screenshot
        previousCursor = NSCursor.current
        BackgroundCursor.setAllowed(true)
        panels = screens.map(makePanel)

        selectionStartedAt = Date()
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
        for preview in previews { preview.dismiss() }
        closeAllPins()
        lastCapture = nil
    }

    /// Adds a thumbnail to the row. The row stays centered, so an arriving thumbnail slides the
    /// others aside rather than landing on top of them.
    func showPreview(
        for image: CGImage, from sourceRect: CGRect?,
        onOpen: @escaping () -> Void,
        onPin: @escaping (CGSize, CGPoint) -> ScreenshotPinWindow?
    ) {
        let preview = ScreenshotPreviewHUD()
        preview.onOpen = onOpen
        preview.onPin = onPin
        preview.onDismissed = { [weak self, weak preview] in
            guard let self, let preview else { return }
            previews.removeAll { $0 === preview }
            if previews.isEmpty { previewScreen = nil }
            layoutPreviews()
            armPreviewReturnKey()
        }
        preview.prepare(image, visibleFor: previewDuration)
        if previews.isEmpty {
            previewScreen =
                NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
        }
        for existing in previews { existing.extendVisibility(previewDuration) }
        previews.append(preview)
        layoutPreviews(presenting: preview, from: sourceRect)
        armPreviewReturnKey()
    }

    /// Lays the row out centered on `previewScreen`, bottoms aligned at the HUD margin so
    /// thumbnails of different shapes sit on one line.
    private func layoutPreviews(
        presenting arriving: ScreenshotPreviewHUD? = nil, from sourceRect: CGRect? = nil
    ) {
        guard let visible = previewScreen?.visibleFrame else { return }
        let widths = previews.map(\.cardSize.width)
        let total = widths.reduce(0, +) + Self.previewGap * CGFloat(max(previews.count - 1, 0))
        var x = visible.midX - total / 2
        for preview in previews {
            let center = CGPoint(
                x: x + preview.cardSize.width / 2,
                y: visible.minY + Theme.Size.hudBottomMargin + preview.cardSize.height / 2)
            if preview === arriving {
                preview.present(at: center, from: sourceRect)
            } else {
                preview.move(to: center)
            }
            x += preview.cardSize.width + Self.previewGap
        }
    }

    /// Return always opens the newest thumbnail — but only for the moment right after the capture.
    /// Carbon consumes Return system-wide while the key is held, so a thumbnail left up while the
    /// user goes back to typing would eat the Return that sends their message. The claim therefore
    /// ends at the first of: a click anywhere outside Spotter, the row emptying, or the grace
    /// window below, whichever the thumbnail's own countdown happens to be.
    private static let previewReturnGrace: Duration = .seconds(5)

    private func armPreviewReturnKey() {
        returnGrace?.cancel()
        returnGrace = nil
        guard previews.last != nil else {
            releasePreviewReturnKey()
            return
        }
        hotKeys.holdTransientKey(
            id: Self.previewReturnKeyID,
            shortcut: KeyShortcut(carbonKeyCode: kVK_Return, carbonModifiers: 0)
        ) { [weak self] in
            self?.previews.last?.open()
        }
        observeReturnHandback()
        returnGrace = Task { [weak self] in
            try? await Task.sleep(for: Self.previewReturnGrace)
            guard !Task.isCancelled else { return }
            self?.releasePreviewReturnKey()
        }
    }

    /// A click anywhere outside Spotter means the user is working again, so Return goes back to
    /// them. The monitor reads nothing off the event — not its location, not its window — and is
    /// torn down the moment it fires.
    private func observeReturnHandback() {
        guard returnHandback == nil else { return }
        returnHandback = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releasePreviewReturnKey() }
        }
    }

    private func releasePreviewReturnKey() {
        returnGrace?.cancel()
        returnGrace = nil
        if let returnHandback {
            NSEvent.removeMonitor(returnHandback)
            self.returnHandback = nil
        }
        hotKeys.releaseTransientKey(id: Self.previewReturnKeyID)
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
            visibleFrame: screen.visibleFrame,
            roundedCorners: roundedCorners)
        let panel = ScreenshotSelectionPanel(screen: screen, contentView: view)
        view.onSelection = { [weak self, weak screen] localRect in
            guard let self, let screen else { return }
            finishSelection(localRect, on: screen)
        }
        view.onColorPick = { [weak self, weak screen] localPoint in
            guard let self, let screen else { return }
            pickColor(at: localPoint, on: screen)
        }
        view.onWindowCapture = { [weak self] in self?.captureWindowUnderPointer() }
        view.onScreenCapture = { [weak self, weak screen] in
            guard let self, let screen else { return }
            captureScreen(of: screen)
        }
        view.onToggleMode = { [weak self] in self?.toggleMode() }
        view.onCancel = { [weak self] in self?.cancel() }
        return panel
    }

    private func toggleMode() {
        mode = mode.next
        applyMode()
    }

    private func applyMode() {
        AppLog.info("screenshot", "Capture mode is now \(mode).")
        for panel in panels { panel.apply(mode: mode) }
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
        lastCaptureRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        if mode == .ocr {
            recognizeText(in: captureRect, displayID: displayID)
            return
        }
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

    /// Captures the dragged region only to read it: the pixels are recognized and dropped, and the
    /// text lands on the clipboard in their place. Always captured at Retina regardless of the
    /// Resolution setting — recognition accuracy tracks pixel density, and no image is kept, so
    /// honouring a 1x preference here would cost accuracy and save nothing.
    private func recognizeText(in rect: CGRect, displayID: CGDirectDisplayID) {
        dismissPanels()
        captureTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                let image = try await Self.captureImage(
                    in: rect, displayID: displayID, scale: .retina)
                let text = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotTextRecognizer.text(in: image)
                }.value
                guard !Task.isCancelled else { return }
                captureTask = nil
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    AppLog.info("screenshot", "Text recognition found nothing in the selection.")
                    finish(.noTextFound)
                    return
                }
                writeTextToPasteboard(trimmed)
                AppLog.info("screenshot", "Copied \(trimmed.count) recognized character(s).")
                finish(.textCopied)
            } catch {
                AppLog.error("screenshot", "Text recognition failed: \(error.localizedDescription)")
                captureTask = nil
                finish(.failed)
            }
        }
    }

    /// The whole display whose glass button was clicked, captured through the same display path a
    /// region uses — the source rectangle is simply the display's full bounds.
    private func captureScreen(of screen: NSScreen) {
        guard let displayID = screen.displayID else {
            cancel()
            return
        }
        let captureRect = CGRect(origin: .zero, size: screen.frame.size)
        let captureScale = captureScale
        lastCaptureRect = screen.frame
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

    /// A right click captures the window under the pointer, hit-tested once at the click itself. A
    /// window image already carries its own rounded alpha corners, so it skips the corner pass.
    private func captureWindowUnderPointer() {
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let point = ScreenshotWindowPicker.displaySpacePoint(
            fromAppKit: NSEvent.mouseLocation, primaryScreenMaxY: primaryScreenMaxY)
        guard
            let target = ScreenshotWindowPicker.target(
                at: point,
                in: Self.windowCandidates(),
                excluding: ProcessInfo.processInfo.processIdentifier)
        else {
            // Nothing under the pointer is a no-op, not a cancel; the selection stays up.
            AppLog.info("screenshot", "Right click found no window under the pointer.")
            return
        }
        let captureScale = captureScale
        let includesWindowShadow = includesWindowShadow
        lastCaptureRect = ScreenshotWindowPicker.appKitRect(
            fromDisplaySpace: target.bounds, primaryScreenMaxY: primaryScreenMaxY)
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

    /// Captures one point only to name it: the pixel is sampled, the image is dropped, and the hex
    /// value goes to the clipboard. Sampled at 1x regardless of the Resolution setting — one point
    /// is the colour the user sees, and averaging its Retina quad is the honest single value.
    private func pickColor(at localPoint: CGPoint, on screen: NSScreen) {
        guard let displayID = screen.displayID else {
            cancel()
            return
        }
        let sampleRect = ScreenshotGeometry.colorSampleRect(
            around: localPoint, within: CGRect(origin: .zero, size: screen.frame.size))
        let captureRect = ScreenshotGeometry.captureRect(
            fromScreenLocal: sampleRect, screenHeight: screen.frame.height)
        dismissPanels()

        captureTask = Task { [weak self] in
            guard let self else { return }
            // The overlay's hit surface carries one alpha step of black, so the sample waits for
            // WindowServer to remove the panels the same way a region capture does.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                let image = try await Self.captureImage(
                    in: captureRect, displayID: displayID, scale: .oneX)
                let hex = await Task.detached(priority: .userInitiated) {
                    ScreenshotColorSampler.hexColor(from: image)
                }.value
                guard !Task.isCancelled else { return }
                captureTask = nil
                guard let hex else {
                    finish(.failed)
                    return
                }
                writeTextToPasteboard(hex)
                AppLog.info("screenshot", "Copied the sampled colour \(hex).")
                finish(.colorCopied(hex))
            } catch {
                AppLog.error("screenshot", "Colour sampling failed: \(error.localizedDescription)")
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
        lastCapture = ScreenshotCapturePayload(
            image: image, roundedCorners: roundedCorners, sourceAppName: captureSource?.name,
            sourceBundleID: captureSource?.bundleID)
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

    /// Deliberately unmarked, unlike every other Spotter write: recognized text and a sampled hex
    /// value are the user's own content and belong in clipboard history, where an image capture —
    /// which has its own thumbnail, pin and editor — does not. Owner decision, Aug 2026.
    private func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
        selectionStartedAt = nil
        hotKeys.releaseTransientKey(id: Self.escapeKeyID)
        for panel in panels { panel.deactivate() }
        panels = []
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

    func apply(mode: ScreenshotCaptureMode) {
        selectionView.apply(mode: mode)
    }

    func deactivate() {
        orderOut(nil)
    }
}

private final class ScreenshotSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onColorPick: ((CGPoint) -> Void)?
    var onWindowCapture: (() -> Void)?
    var onScreenCapture: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var onCancel: (() -> Void)?

    private let roundedCorners: Bool
    private let screenFrame: CGRect
    private var mode: ScreenshotCaptureMode = .screenshot
    private var cursor: NSCursor { ScreenshotCursor.cursor(for: mode) }
    private var dragStart: CGPoint?
    private var selection: CGRect?
    /// The glass button's footprint; the pointer over it is the plain arrow, not the crosshair.
    private let screenButtonFrame: CGRect
    /// Created lazily so its action can capture `self`.
    private lazy var screenButton = ScreenshotScreenButtonHost(
        rootView: ScreenshotScreenButton { [weak self] in self?.onScreenCapture?() })
    private static let selectionStrokeWidthPixels: CGFloat = 1

    init(screenFrame: CGRect, visibleFrame: CGRect, roundedCorners: Bool) {
        self.roundedCorners = roundedCorners
        self.screenFrame = screenFrame
        screenButtonFrame = ScreenshotGeometry.screenButtonFrame(
            screenFrame: screenFrame, visibleFrame: visibleFrame)
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        screenButton.frame = screenButtonFrame
        addSubview(screenButton)
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
        if !screenButton.isHidden { addCursorRect(screenButtonFrame, cursor: .arrow) }
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
        // Whole-screen capture is a picture; the button sits out the text and colour modes.
        screenButton.isHidden = mode != .screenshot
        refreshCursorRects()
        needsDisplay = true
    }

    /// The glass button owns the pointer over its own footprint.
    private func setPointerCursor() {
        if !screenButton.isHidden, screenButtonFrame.contains(localPointerLocation()) {
            NSCursor.arrow.set()
        } else {
            cursor.set()
        }
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
        guard event.buttonNumber == 0 else { return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        cursor.set()
        guard mode.isDragSelection else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        dragStart = point
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode.isDragSelection, let dragStart else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        selection = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
        cursor.set()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        let point = ScreenshotGeometry.clampedPoint(convert(event.locationInWindow, from: nil), to: bounds)
        if mode == .colorPicker {
            onColorPick?(point)
            return
        }
        guard let dragStart else { return }
        let rect = ScreenshotGeometry.selectionRect(from: dragStart, to: point, within: bounds)
        self.dragStart = nil
        selection = nil
        if ScreenshotGeometry.isCapturable(rect) {
            onSelection?(rect)
        } else {
            onCancel?()
        }
    }

    /// A right click is the window capture, hit-tested where it lands. It no longer cancels in any
    /// mode — Escape and a second shortcut press remain the ways out — and it is inert mid-drag and
    /// outside screenshot mode, where a window picture would be a surprise.
    override func rightMouseDown(with event: NSEvent) {
        guard mode == .screenshot, dragStart == nil else { return }
        onWindowCapture?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onCancel?()
        case 49:
            onToggleMode?()
        // Tab is the keyboard's screen button: the whole display, only where the button itself shows (screenshot mode, no drag in flight).
        case 48 where mode == .screenshot && dragStart == nil:
            onScreenCapture?()
        default:
            super.keyDown(with: event)
        }
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
