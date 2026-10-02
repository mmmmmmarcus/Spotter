import SwiftUI

struct ClipboardTypeMenu: View {
    let filter: ClipboardFilter
    let select: (ClipboardFilter) -> Void

    var body: some View {
        Menu {
            Picker("Clipboard type", selection: Binding(get: { filter }, set: select)) {
                ForEach(ClipboardFilter.allCases, id: \.self) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Label(filter.title, systemImage: filter.systemImage)
                Image(systemName: "chevron.down")
            }
            .font(Theme.Typography.bar)
            .symbolRenderingMode(.monochrome)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frosted(in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focusable(false)
        .help("Clipboard type (⌘P / ⇧⌘P)")
        .accessibilityLabel("Clipboard type")
        .accessibilityValue(filter.title)
    }
}
