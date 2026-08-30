import AppKit
import SwiftUI

/// The whole-screen capture control: one Liquid Glass square per display, floating beside the Dock
/// while a selection is up. Clicking it captures that display in full.
struct ScreenshotScreenButton: View {
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        Button(action: action) {
            Image(systemName: "display")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: ScreenshotGeometry.screenButtonSize.width,
                    height: ScreenshotGeometry.screenButtonSize.height)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: shape)
    }
}

/// Accepts the first click while the user's app stays frontmost, like the selection view around it.
final class ScreenshotScreenButtonHost: NSHostingView<ScreenshotScreenButton> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: ScreenshotScreenButton) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    @MainActor @preconcurrency required init?(coder: NSCoder) { fatalError() }
}
