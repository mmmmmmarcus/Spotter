import SwiftUI

/// The category picker shared by the Settings and onboarding Raycast-import screens: a 3-column grid of checkboxes over one `RaycastImportOptions` bitset, plus a Select All / Deselect All link.
struct RaycastImportSelection: View {
    @Binding var selection: RaycastImportOptions

    private struct Category: Identifiable {
        let option: RaycastImportOptions
        let label: String
        var id: Int { option.rawValue }
    }

    private static let categories: [Category] = [
        .init(option: .shortcuts, label: "Shortcuts"),
        .init(option: .favorites, label: "Favorites"),
        .init(option: .emojiSkinTone, label: "Emoji skin tone"),
        .init(option: .launchAtLogin, label: "Launch at login"),
        .init(option: .menuBarVisibility, label: "Menu-bar icon"),
        .init(option: .clipboardHistory, label: "Clipboard history"),
        .init(option: .popToRoot, label: "Pop to root"),
        .init(option: .compactMode, label: "Compact mode"),
    ]

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .leading), count: 3)

    private func included(_ option: RaycastImportOptions) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { selection = $0 ? selection.union(option) : selection.subtracting(option) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(Self.categories) { category in
                    Toggle(isOn: included(category.option)) {
                        Text(category.label).lineLimit(1)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Button(selection == .all ? "Deselect All" : "Select All") {
                selection = selection == .all ? [] : .all
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
