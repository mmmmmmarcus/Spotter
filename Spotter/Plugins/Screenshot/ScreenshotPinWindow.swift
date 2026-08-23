import AppKit
import SwiftUI

/// A capture torn off the preview thumbnail and left floating above every app. Dragging the body
/// moves it, dragging a corner resizes it, a click opens the editor, and scrolling works it exactly
/// as the thumbnail does — lift to edit, push down to dismiss. Every pointer decision is resolved in
/// AppKit rather than SwiftUI: the same surface has to tell a click from a drag from a resize, which
/// one gesture recognizer cannot.
@MainActor
final class ScreenshotPinWindow {
    /// How much bigger than the preview thumbnail a fresh pin lands.
    static let magnification: CGFloat = 3
    /// Corner square that starts a resize instead of a move.
    static let cornerGrab: CGFloat = 18
    static let minimumWidth: CGFloat = 120
    private static let appearDuration: TimeInterval = 0.24
    private static let closeDuration: TimeInterval = 0.16

    let capture: ScreenshotCapturePayload
    /// Fired by a click on the artwork, or by a scroll that lifts it.
    var onOpen: ((ScreenshotCapturePayload) -> Void)?
    /// Fired once the close animation has played, so the owner can drop its reference.
    var onClose: ((ScreenshotPinWindow) -> Void)?

    private let model = PinModel()
    private var panel: NSPanel?
    private var closing = false
    /// Taken from the thumbnail actually on screen, not from the raw image: the card includes its
    /// frame, so resizing by the image's own ratio would shift the shape on the first drag.
    private var aspect: CGFloat = 1

    init(capture: ScreenshotCapturePayload) {
        self.capture = capture
        model.image = capture.image
    }

    /// Lands at full size centred on the pointer and scales up into it. The window frame is final
    /// from the first frame on purpose — animating it would fight the drag that is still running.
    func present(from thumbnail: CGSize, at center: CGPoint) {
        aspect = thumbnail.width > 0 ? thumbnail.height / thumbnail.width : 1
        let card = CGSize(
            width: (thumbnail.width * Self.magnification).rounded(),
            height: (thumbnail.height * Self.magnification).rounded())
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(Self.frame(card: card, center: center), display: false)
        panel.orderFrontRegardless()
        model.scale = 1 / Self.magnification
        model.opacity = 0
        withAnimation(.easeOut(duration: Self.appearDuration)) {
            model.scale = 1
            model.opacity = 1
        }
    }

    /// Follows the pointer while the tear-off drag is still held.
    func move(center: CGPoint) {
        guard let panel else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: (center.x - size.width / 2).rounded(),
                y: (center.y - size.height / 2).rounded()))
    }

    func close() {
        guard let panel, !closing else { return }
        closing = true
        withAnimation(.easeIn(duration: Self.closeDuration)) {
            model.scale = 0.92
            model.opacity = 0
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.closeDuration * 1000) + 20))
            panel.orderOut(nil)
            guard let self else { return }
            self.panel = nil
            onClose?(self)
        }
    }

    /// Opening consumes the pin: the same capture is about to appear in a window that can actually
    /// edit it, so leaving the floating copy behind would be two of the same thing on screen.
    private func open() {
        let capture = capture
        let onOpen = onOpen
        close()
        onOpen?(capture)
    }

    /// The panel is the card plus the room its shadow needs on every side.
    private static func frame(card: CGSize, center: CGPoint) -> NSRect {
        let padding = ScreenshotPreviewHUD.shadowPadding
        let size = CGSize(width: card.width + padding * 2, height: card.height + padding * 2)
        return NSRect(
            x: (center.x - size.width / 2).rounded(),
            y: (center.y - size.height / 2).rounded(),
            width: size.width,
            height: size.height)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = PinHostingView(rootView: ScreenshotPinView(model: model))
        host.aspect = aspect
        host.onClick = { [weak self] in self?.open() }
        host.onFlick = { [weak self] direction in
            guard let self else { return }
            switch direction {
            case .up: open()
            case .down: close()
            }
        }
        PanelHosting.install(host, in: panel)
        return panel
    }
}

/// Owns every pointer decision for a pinned window: move, resize, click, or flick.
private final class PinHostingView<Content: View>: NSHostingView<Content> {
    var aspect: CGFloat = 1
    var onClick: (() -> Void)?
    var onFlick: ((ScreenshotScrollFlick.Direction) -> Void)?

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private enum Drag {
        case moving(origin: NSPoint, mouse: NSPoint)
        case resizing(corner: Corner, frame: NSRect, mouse: NSPoint)
    }

    private var drag: Drag?
    private var moved = false
    private var flick = ScreenshotScrollFlick()
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let corner = corner(at: point) {
            NSCursor.frameResize(position: position(of: corner), directions: .all).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if let direction = flick.direction(for: event) { onFlick?(direction) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        moved = false
        if let corner = corner(at: convert(event.locationInWindow, from: nil)) {
            drag = .resizing(corner: corner, frame: window.frame, mouse: NSEvent.mouseLocation)
        } else {
            drag = .moving(origin: window.frame.origin, mouse: NSEvent.mouseLocation)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        let mouse = NSEvent.mouseLocation
        switch drag {
        case .moving(let origin, let start):
            let delta = CGPoint(x: mouse.x - start.x, y: mouse.y - start.y)
            guard moved || hypot(delta.x, delta.y) >= 3 else { return }
            moved = true
            window.setFrameOrigin(
                NSPoint(x: (origin.x + delta.x).rounded(), y: (origin.y + delta.y).rounded()))
        case .resizing(let corner, let frame, let start):
            moved = true
            window.setFrame(
                resized(
                    frame, corner: corner,
                    by: CGPoint(x: mouse.x - start.x, y: mouse.y - start.y)),
                display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = drag != nil
        drag = nil
        // A press that never travelled is a click, and a click opens the capture for editing.
        if wasDragging, !moved { onClick?() }
        moved = false
    }

    /// Aspect-locked, with the dragged corner's opposite held still. Both axes contribute, so a
    /// diagonal drag tracks the pointer instead of answering only to horizontal movement.
    private func resized(_ frame: NSRect, corner: Corner, by delta: CGPoint) -> NSRect {
        let padding = ScreenshotPreviewHUD.shadowPadding * 2
        let growsRight = corner == .topRight || corner == .bottomRight
        // AppKit's y grows upward, so a *visually* downward drag is a negative delta.
        let growsDown = corner == .bottomLeft || corner == .bottomRight
        let fromX = growsRight ? delta.x : -delta.x
        let fromY = (growsDown ? -delta.y : delta.y) / max(aspect, 0.0001)
        let card = max(
            frame.width - padding + (fromX + fromY) / 2, ScreenshotPinWindow.minimumWidth)
        let size = CGSize(width: card + padding, height: (card * aspect).rounded() + padding)
        // Hold the corner opposite the one being dragged, in AppKit's bottom-left origin.
        let x = growsRight ? frame.minX : frame.maxX - size.width
        let y = growsDown ? frame.maxY - size.height : frame.minY
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// `NSHostingView` is flipped, so a converted point already has a top-left origin.
    private func corner(at point: NSPoint) -> Corner? {
        let padding = ScreenshotPreviewHUD.shadowPadding
        let card = bounds.insetBy(dx: padding, dy: padding)
        let grab = ScreenshotPinWindow.cornerGrab
        let top = isFlipped ? card.minY : card.maxY - grab
        let bottom = isFlipped ? card.maxY - grab : card.minY
        if NSRect(x: card.minX, y: top, width: grab, height: grab).contains(point) {
            return .topLeft
        }
        if NSRect(x: card.maxX - grab, y: top, width: grab, height: grab).contains(point) {
            return .topRight
        }
        if NSRect(x: card.minX, y: bottom, width: grab, height: grab).contains(point) {
            return .bottomLeft
        }
        if NSRect(x: card.maxX - grab, y: bottom, width: grab, height: grab).contains(point) {
            return .bottomRight
        }
        return nil
    }

    private func position(of corner: Corner) -> NSCursor.FrameResizePosition {
        switch corner {
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
    }
}

@MainActor
private final class PinModel: ObservableObject {
    @Published var image: CGImage?
    @Published var scale: CGFloat = 1
    @Published var opacity: CGFloat = 1
}

private struct ScreenshotPinView: View {
    @ObservedObject var model: PinModel

    var body: some View {
        if let image = model.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ScreenshotPreviewHUD.cornerRadius, style: .continuous))
                // The same white frame the preview thumbnail wears, so a pin reads as that thumbnail grown.
                .padding(ScreenshotPreviewHUD.borderWidth)
                .background(
                    RoundedRectangle(
                        cornerRadius: ScreenshotPreviewHUD.cornerRadius
                            + ScreenshotPreviewHUD.borderWidth,
                        style: .continuous
                    )
                    .fill(.white))
                .shadow(
                    color: .black.opacity(ScreenshotPreviewHUD.shadowOpacity),
                    radius: ScreenshotPreviewHUD.shadowRadius / 2,
                    x: 0,
                    y: ScreenshotPreviewHUD.shadowOffsetY)
                .padding(ScreenshotPreviewHUD.shadowPadding)
                .scaleEffect(model.scale)
                .opacity(model.opacity)
        }
    }
}
