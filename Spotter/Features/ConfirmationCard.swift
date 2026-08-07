import SwiftUI

/// The in-palette yes/no card — every destructive flow confirms here, never in a system dialog.
/// Keyboard: ←/→/Tab move the highlight, ↵ activates it, Esc cancels; the highlight starts on
/// Cancel so a reflexive second ↵ can never be the confirmation.
struct ConfirmationCard: View {
    let confirmation: PaletteConfirmation
    @Binding var selection: Int
    let onActivate: (Bool) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(confirmation.title)
                .font(Theme.Typography.rowTitle.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(confirmation.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.md) {
                button("Cancel", index: 0, destructive: false) { onActivate(false) }
                button(confirmation.actionTitle, index: 1, destructive: confirmation.isDestructive) {
                    onActivate(true)
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: Theme.Size.confirmationWidth)
        // Same glass as PopoverMenu — Tahoe glass owns its elevation, no hand-tuned shadow.
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous))
    }

    private func button(
        _ title: String, index: Int, destructive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.bar)
                .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(selection == index ? Theme.Colors.selection : Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(
                            selection == index ? Theme.Colors.border : Theme.Colors.cardStroke,
                            lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { selection = index }
        }
    }
}
