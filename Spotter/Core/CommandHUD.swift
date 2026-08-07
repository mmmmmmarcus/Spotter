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
        model.feedback = feedback
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
        let host = NSHostingView(rootView: CommandHUDView(model: model))
        // Same reason as the palette: SwiftUI must not drive the window frame.
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    /// Centered horizontally, sitting above the bottom of the visible frame — the placement macOS
    /// uses for its own volume and brightness HUDs, and clear of both the Dock and the menu bar.
    private func position(_ panel: NSPanel) {
        guard let host = panel.contentView else { return }
        let size = host.fittingSize
        let screen =
            NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
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
}

/// Plain observable box so the panel is built once and only its content changes between commands.
@MainActor
private final class Model: ObservableObject {
    @Published var feedback: SystemCommandFeedback?
}

private struct CommandHUDView: View {
    @ObservedObject var model: Model

    var body: some View {
        if let feedback = model.feedback {
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
