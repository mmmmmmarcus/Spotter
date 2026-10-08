import SwiftUI

/// AppKit resolves the named base symbol directly, without inheriting a button variant.
private struct HeaderMenuSymbol: View {
    let name: String
    let size: CGFloat

    var body: some View {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        if let image = NSImage(
            systemSymbolName: SystemSymbolName.resolve(name), accessibilityDescription: nil
        )?
        .withSymbolConfiguration(configuration) {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: size, height: size)
        }
    }
}

/// A bar control's hover chrome; footer pills and header pop-ups share `barControl` as one family.
enum ExtensionBarButtonChrome {
    case capsule
    case rounded

    func shape(_ metrics: ExtensionMetrics) -> AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .rounded:
            return AnyShape(
                RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous))
        }
    }
}

/// A palette bar control, bare until hover; hover lives here so its owner never re-renders.
struct ExtensionBarButton<Label: View>: View {
    var chrome: ExtensionBarButtonChrome = .capsule
    var isSelected = false
    /// `sm` padding, so a 16-point glyph frame makes a square as tall as the bar.
    var isCompact = false
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let shape = chrome.shape(metrics)
        return Button(action: action) {
            label
                .padding(.horizontal, isCompact ? metrics.spacing.sm : metrics.spacing.md)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    /// Selection beats hover, the rule every row follows.
    private var fill: Color {
        if isSelected { return Theme.Raycast.Colors.selection }
        return hovered ? Theme.Raycast.Colors.rowHover : Color.clear
    }
}

/// A header control that states the active choice and opens an in-window menu.
