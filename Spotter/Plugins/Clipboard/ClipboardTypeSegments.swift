import SwiftUI

struct ClipboardTypeSegments: View {
    let filter: ClipboardFilter
    let select: (ClipboardFilter) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ClipboardFilter.allCases, id: \.self) { option in
                Button { select(option) } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .labelStyle(.iconOnly)
                        .font(Theme.Typography.bar)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(filter == option ? .primary : .secondary)
                        .frame(width: Theme.Size.clipboardFilterSegmentWidth,
                               height: Theme.Size.clipboardFilterSegmentWidth)
                        .background {
                            if filter == option {
                                Capsule()
                                    .fill(Theme.Colors.selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // The shared search field remains the palette's keyboard target.
                .focusable(false)
                .help(option.title)
                .accessibilityAddTraits(filter == option ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.xxs)
        .frosted(in: Capsule())
        .animation(nil, value: filter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clipboard type")
    }
}
