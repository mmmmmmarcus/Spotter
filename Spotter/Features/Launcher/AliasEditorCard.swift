import SwiftUI

/// The in-palette alias editor, opened from ⌘K → Set Alias. Same glass and corner as the Actions
/// menu it replaces, so one panel hands off to the other in place. Deliberately does *not* set
/// `PaletteViewModel.menuOpen`: that freeze exists to keep a menu's keystrokes out of the search
/// field, and here the keystrokes are the point.
struct AliasEditorCard: View {
    let entry: AppEntry
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Alias")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)

            TextField("", text: $draft, prompt: Text("Type an alias…"))
                .textFieldStyle(.plain)
                .font(Theme.Typography.rowTitle)
                .focused(isFocused)
                // The system focus ring insets the field editor, hopping the placeholder left.
                .focusEffectDisabled()
                .onSubmit(onSave)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )

            HStack(spacing: Theme.Spacing.sm) {
                AppIconView(app: entry)
                    .frame(width: 16, height: 16)
                Text(entry.name)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.md)
                footerButton("Close", cap: "esc", action: onClose)
                footerButton("Save", cap: "↵", action: onSave)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.menuWidth + 60)
        // Same glass as PopoverMenu — Tahoe glass owns its elevation, no hand-tuned shadow.
        .glassEffect(
            .regular, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous))
    }

    private func footerButton(_ title: String, cap: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                KeyCapChip(text: cap, style: .outline)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: 26)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
