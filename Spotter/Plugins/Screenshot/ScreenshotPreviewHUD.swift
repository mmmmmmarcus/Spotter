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

    private let model = Model()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var activationObserver: NotificationToken?
    private unowned let hotKeys: HotKeyManager

    init(hotKeys: HotKeyManager) {
        self.hotKeys = hotKeys
        model.onTap = { [weak self] in self?.open() }
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
        withAnimation(.easeOut(duration: Self.appearDuration)) {
            model.isPresented = true
        }

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
        // The panel frame is set here, not by SwiftUI — same rule as the palette and the command HUD.
        host.sizingOptions = []
        panel.contentView = host
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

/// Clicks must land while Spotter is inactive — the panel never becomes key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class Model: ObservableObject {
    @Published var image: CGImage?
    @Published var thumbnailSize: CGSize = ScreenshotPreviewHUD.maximumSize
    @Published var isPresented = false
    var onTap: (() -> Void)?
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
                .shadow(
                    color: .black.opacity(ScreenshotPreviewHUD.shadowOpacity),
                    radius: ScreenshotPreviewHUD.shadowRadius / 2,
                    x: 0,
                    y: ScreenshotPreviewHUD.shadowOffsetY)
                .contentShape(Rectangle())
                .onTapGesture { model.onTap?() }
                .onHover { model.onHover?($0) }
                // Blurs into focus and back out, in place: no scale or offset, so nothing about the thumbnail moves while it appears.
                .blur(radius: model.isPresented ? 0 : ScreenshotPreviewHUD.appearBlur)
                .opacity(model.isPresented ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
