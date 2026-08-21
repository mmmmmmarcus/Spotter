import AppKit
import SwiftUI

/// A brief floating confirmation for a command whose effect is otherwise invisible — "Trash Emptied",
/// "No Disks to Eject". Show Desktop or Hide Others need none: they are their own confirmation.
///
/// The panel is non-activating and ignores the mouse. A command has just acted on the app the user
/// came from, and stealing focus back to report on it would undo the thing being reported.
@MainActor
final class CommandHUD {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private let model = Model()

    /// Long enough to read three words, short enough not to sit over the app the user returned to.
    private static let visibleDuration: Duration = .milliseconds(1400)
    private static let fadeOut: TimeInterval = 0.22

    func show(_ feedback: SystemCommandFeedback) {
        show(title: feedback.title, symbol: feedback.symbol, isNoOp: feedback.isNoOp)
    }

    /// The generic entry any subsystem can use — a finished background run, not just system commands.
    func show(title: String, symbol: String, isNoOp: Bool = false) {
        model.content = Content(title: title, symbol: symbol, isNoOp: isNoOp)
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        // A second command mid-fade must read as a fresh HUD, not resume the one dissolving.
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            // A show() landing during the fade already reset alpha; ordering out now would kill it.
            guard let panel, panel.alphaValue == 0 else { return }
            panel.orderOut(nil)
        }
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
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // A subview, not the contentView: the content-view extrema path crashes macOS 26 (see PanelHosting). Sizing stays ours either way; `contentSize()` measures off-window.
        PanelHosting.install(NSHostingView(rootView: CommandHUDView(model: model)), in: panel)
        return panel
    }

    /// Centered horizontally, sitting above the bottom of the visible frame — the placement macOS
    /// uses for its own volume and brightness HUDs, and clear of both the Dock and the menu bar.
    private func position(_ panel: NSPanel) {
        let size = contentSize()
        guard size.width > 0, size.height > 0 else { return }
        // NSMouseInRect, not contains: the mouse y sits on frame.maxY on the top edge, which a
        // plain rect-contains misses (same reasoning as PaletteWindowController's screen pick).
        let screen =
            NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + Theme.Size.hudBottomMargin,
                width: size.width,
                height: size.height),
            display: false)
    }

    /// Measured on a throwaway hosting view that is never installed in a window: a hosting view with
    /// no window cannot post a constraint update to one, and it reports the current content's size
    /// immediately, where the panel's own host — deliberately sizing-optionless — reports zero.
    private func contentSize() -> CGSize {
        let probe = NSHostingView(rootView: CommandHUDView(model: model))
        probe.sizingOptions = [.intrinsicContentSize]
        return probe.fittingSize
    }
}

/// What the HUD renders, detached from any one feature's feedback type.
private struct Content {
    let title: String
    let symbol: String
    let isNoOp: Bool
}

/// Plain observable box so the panel is built once and only its content changes between commands.
@MainActor
private final class Model: ObservableObject {
    @Published var content: Content?
}

private struct CommandHUDView: View {
    @ObservedObject var model: Model

    var body: some View {
        if let feedback = model.content {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: feedback.symbol)
                    .font(Theme.Typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    // A no-op reports that nothing happened, so it reads quieter than a real change.
                    .foregroundStyle(feedback.isNoOp ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                Text(feedback.title)
                    .font(Theme.Typography.bar)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
            // Glass with no hand-tuned shadow, matching PopoverMenu — Tahoe glass owns its elevation.
            .glassEffect(
                .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous))
            .fixedSize()
        }
    }
}
