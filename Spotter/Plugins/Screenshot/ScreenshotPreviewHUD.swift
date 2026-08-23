import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The post-capture thumbnail: the shot itself in a white frame near the bottom of the screen, with
/// no text, symbol or button. Clicking it or pressing Return opens the editor; focusing another app
/// dismisses it. Like `CommandHUD` the panel never becomes key, so Spotter never takes focus from
/// the app the capture came from — which is also why Return arrives through a transient system key
/// rather than through the responder chain.
@MainActor
final class ScreenshotPreviewHUD {
    /// Outer thumbnail bounds from the design; the capture is aspect-fitted inside the border.
    static let maximumSize = CGSize(width: 124, height: 73)
    static let borderWidth: CGFloat = 4
    static let cornerRadius: CGFloat = 4
    static let shadowRadius: CGFloat = 16
    static let shadowSpread: CGFloat = 4
    static let shadowOffsetY: CGFloat = 4
    static let shadowOpacity: CGFloat = 0.4
    /// Room for the blur, its spread and its downward offset, so no edge of the shadow is clipped.
    /// Also absorbs `appearBlur`, which spreads the artwork past its own bounds while it resolves.
    static let shadowPadding = shadowRadius + shadowSpread + shadowOffsetY
    /// The thumbnail resolves from out-of-focus to sharp in place; enough to read as a blur on a
    /// 124-point frame without smearing into a cloud.
    static let appearBlur: CGFloat = 10
    static let appearDuration: TimeInterval = 0.26
    static let disappearDuration: TimeInterval = 0.18

    private static let transientKeyID = "screenshot.preview.return"
    private static let visibleDuration: Duration = .milliseconds(3500)

    /// Fired by a click or by Return while the thumbnail is up.
    var onOpen: (() -> Void)?
    /// Fired when the thumbnail is dragged off, with the pointer position it was torn from. The
    /// pin it returns keeps following the same uninterrupted drag.
    var onPin: ((CGSize, CGPoint) -> ScreenshotPinWindow?)?

    private let model = Model()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var activationObserver: NotificationToken?
    private var flick = ScreenshotScrollFlick()
    /// The pin torn off by the gesture in flight, so the same drag keeps moving it.
    private var draggingPin: ScreenshotPinWindow?
    private unowned let hotKeys: HotKeyManager

    init(hotKeys: HotKeyManager) {
        self.hotKeys = hotKeys
        model.onHover = { [weak self] hovering in
            guard let self else { return }
            dismissal?.cancel()
            // Hovering holds the thumbnail so it cannot dissolve under an arriving pointer.
            if !hovering { scheduleDismissal() }
        }
    }

    func show(_ image: CGImage) {
        let thumbnail = Self.thumbnailSize(for: image)
        model.image = image
        model.thumbnailSize = thumbnail

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, thumbnail: thumbnail)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Settle layout at the final geometry first; a first animated frame rendered at a stale size reads as the thumbnail shifting into place.
        panel.contentView?.layoutSubtreeIfNeeded()
        withAnimation(.easeOut(duration: Self.appearDuration)) {
            model.isPresented = true
        }

        flick.reset()
        hotKeys.holdTransientKey(
            id: Self.transientKeyID,
            shortcut: KeyShortcut(carbonKeyCode: kVK_Return, carbonModifiers: 0)
        ) { [weak self] in
            self?.open()
        }
        observeActivation()
        scheduleDismissal()
    }

    func dismiss() {
        guard panel != nil else { return }
        dismissal?.cancel()
        dismissal = nil
        activationObserver = nil
        hotKeys.releaseTransientKey(id: Self.transientKeyID)
        withAnimation(.easeIn(duration: Self.disappearDuration)) {
            model.isPresented = false
        }
        // Order out only once the blur-out has played; a re-show before then cancels this task.
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.disappearDuration * 1000) + 20))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.dismissal = nil
        }
    }

    /// Push the card down to send it away, lift it up to open the editor.
    private func handleScroll(_ event: NSEvent) {
        switch flick.direction(for: event) {
        case .down: dismiss()
        case .up: open()
        case nil: break
        }
    }

    /// Hand the capture to a pinned window that takes over the drag already in progress. The panel
    /// stays alive but invisible until the button comes up, because AppKit keeps delivering this
    /// gesture to the view that received the mouse-down — ordering it out now would end the drag.
    private func tearOff(at point: CGPoint) {
        guard draggingPin == nil else { return }
        panel?.alphaValue = 0
        draggingPin = onPin?(model.thumbnailSize, point)
    }

    private func open() {
        let onOpen = onOpen
        dismiss()
        onOpen?()
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Switching apps means the user has moved on, so the thumbnail stops offering the editor.
    private func observeActivation() {
        let center = NSWorkspace.shared.notificationCenter
        activationObserver = NotificationToken(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            },
            center: center)
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
        let host = FirstMouseHostingView(rootView: ScreenshotPreviewHUDView(model: model))
        host.onScroll = { [weak self] event in self?.handleScroll(event) }
        host.onClick = { [weak self] in self?.open() }
        host.onDragOff = { [weak self] point in self?.tearOff(at: point) }
        host.onDragMove = { [weak self] point in self?.draggingPin?.move(center: point) }
        host.onDragEnd = { [weak self] in
            guard let self, draggingPin != nil else { return }
            draggingPin = nil
            dismiss()
        }
        // A subview, not the contentView (see PanelHosting): the blur animating during a display-cycle constraint flush is exactly the timing the content-view extrema path crashes on. The frame is still set here, not by SwiftUI.
        PanelHosting.install(host, in: panel)
        return panel
    }

    /// Centered horizontally on the screen under the pointer, at the command HUD's bottom margin.
    private func position(_ panel: NSPanel, thumbnail: CGSize) {
        let size = CGSize(
            width: thumbnail.width + Self.shadowPadding * 2,
            height: thumbnail.height + Self.shadowPadding * 2)
        let screen =
            NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + Theme.Size.hudBottomMargin - Self.shadowPadding,
                width: size.width,
                height: size.height),
            display: false)
    }

    /// The capture aspect-fitted into the design's box, so a tall region never renders letterboxed.
    static func thumbnailSize(for image: CGImage) -> CGSize {
        ScreenshotThumbnail.outerSize(
            forPixelSize: CGSize(width: image.width, height: image.height),
            maximum: maximumSize,
            border: borderWidth)
    }
}

/// Turns wheel travel into a single up-or-down flick. Shared by the thumbnail and by pinned windows
/// so both read the *physical* gesture: natural scrolling is unwound, so the same finger movement
/// means the same thing either way, and a wheel's notches map to the same two directions.
struct ScreenshotScrollFlick {
    enum Direction { case up, down }

    /// Points of travel before a scroll counts — a deliberate flick, not a stray twitch.
    static let activation: CGFloat = 24

    private var travel: CGFloat = 0
    private var consumed = false

    mutating func reset() {
        travel = 0
        consumed = false
    }

    mutating func direction(for event: NSEvent) -> Direction? {
        if event.phase == .began || event.phase == .mayBegin { reset() }
        guard !consumed else { return nil }
        let delta = event.scrollingDeltaY
        travel += event.isDirectionInvertedFromDevice ? delta : -delta
        guard abs(travel) >= Self.activation else { return nil }
        consumed = true
        return travel > 0 ? .down : .up
    }
}

/// Clicks must land while Spotter is inactive — the panel never becomes key. Pointer handling lives
/// here rather than in SwiftUI because one press has to resolve into either a click or a tear-off,
/// and because SwiftUI has no scroll hook for a view that is not a scroll view.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((NSEvent) -> Void)?
    var onClick: (() -> Void)?
    var onDragOff: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private var pressOrigin: CGPoint?
    private var tearingOff = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        if tearingOff {
            onDragMove?(mouse)
            return
        }
        guard let origin = pressOrigin else { return }
        // Travel that turns a press into a tear-off rather than a click.
        guard hypot(mouse.x - origin.x, mouse.y - origin.y) >= 8 else { return }
        pressOrigin = nil
        tearingOff = true
        onDragOff?(mouse)
    }

    override func mouseUp(with event: NSEvent) {
        if tearingOff {
            tearingOff = false
            onDragEnd?()
            return
        }
        guard pressOrigin != nil else { return }
        pressOrigin = nil
        onClick?()
    }
}

@MainActor
private final class Model: ObservableObject {
    @Published var image: CGImage?
    @Published var thumbnailSize: CGSize = ScreenshotPreviewHUD.maximumSize
    @Published var isPresented = false
    var onHover: ((Bool) -> Void)?
}

private struct ScreenshotPreviewHUDView: View {
    @ObservedObject var model: Model

    var body: some View {
        if let image = model.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: model.thumbnailSize.width - ScreenshotPreviewHUD.borderWidth * 2,
                    height: model.thumbnailSize.height - ScreenshotPreviewHUD.borderWidth * 2)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ScreenshotPreviewHUD.cornerRadius, style: .continuous))
                // The white frame is part of the artwork, like the macOS capture thumbnail, so it stays white in both appearances.
                .padding(ScreenshotPreviewHUD.borderWidth)
                .background(
                    RoundedRectangle(
                        cornerRadius: ScreenshotPreviewHUD.cornerRadius
                            + ScreenshotPreviewHUD.borderWidth,
                        style: .continuous
                    )
                    .fill(.white))
                // Blur first, shadow after: the shadow hangs below the card, so blurring a composite that includes it smears its dark mass around asymmetrically and the bright card reads as drifting. Blurred card in, shadow cast at its constant offset outside the blur, nothing moves.
                .blur(radius: model.isPresented ? 0 : ScreenshotPreviewHUD.appearBlur)
                .shadow(
                    color: .black.opacity(ScreenshotPreviewHUD.shadowOpacity),
                    radius: ScreenshotPreviewHUD.shadowRadius / 2,
                    x: 0,
                    y: ScreenshotPreviewHUD.shadowOffsetY)
                .contentShape(Rectangle())
                .onHover { model.onHover?($0) }
                .opacity(model.isPresented ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
