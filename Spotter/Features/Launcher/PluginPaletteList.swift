import SwiftUI

/// Shared launcher-style list for plugin screens; plugins provide data and actions, never their own list chrome.
struct PluginPaletteList: View {
    let sectionTitle: String
    let items: [PluginPaletteItem]
    let selectedID: PluginPaletteItem.ID?
    let scroll: ScrollIntent
    let onActivate: (PluginPaletteItem) -> Void
    let onActions: (PluginPaletteItem) -> Void

    private var selectedIsFirst: Bool {
        selectedID != nil && selectedID == items.first?.id
    }

    // Multi-line result rows (Selection Tools) have heights a LazyVStack can only estimate, which makes `.follow` reveals land short; small lists render eagerly so every offset is exact. Large lists (Kill Process) are single-line fixed-height rows where estimation is safe and laziness matters.
    private var rendersEagerly: Bool {
        items.count <= 40
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rows
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.md)
                    .hideNativeScrollers()
                    .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .onChange(of: scroll) { _, intent in
                switch intent.kind {
                case .top:
                    proxy.scrollToOrigin()
                case .follow:
                    if selectedIsFirst {
                        proxy.scrollToOrigin()
                    } else if let selectedID {
                        proxy.reveal(selectedID)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if rendersEagerly {
            VStack(spacing: 0) { rowContent }
        } else {
            LazyVStack(spacing: 0) { rowContent }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        SectionHeader(title: sectionTitle, isFirst: true)
        ForEach(items) { item in
            PluginPaletteRow(item: item, selected: item.id == selectedID)
                .id(item.id)
                .contentShape(Rectangle())
                .onTapGesture { onActivate(item) }
                .onRightClick { onActions(item) }
        }
    }
}

private struct PluginPaletteRow: View {
    let item: PluginPaletteItem
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            PluginPaletteRowIcon(icon: item.icon)
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.title)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(item.titleLineLimit)
                    .multilineTextAlignment(.leading)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(item.subtitleLineLimit)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            ForEach(Array(item.accessories.enumerated()), id: \.offset) { _, accessory in
                Label(accessory.text, systemImage: accessory.systemImage)
                    .font(Theme.Typography.rowTrailing.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

private struct PluginPaletteRowIcon: View {
    let icon: PluginPaletteIcon
    @State private var fileImage: NSImage?

    init(icon: PluginPaletteIcon) {
        self.icon = icon
        if case .file(let path) = icon {
            _fileImage = State(initialValue: IconCache.cached(forFile: path))
        }
    }

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            case .file:
                if let fileImage {
                    Image(nsImage: fileImage).resizable()
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                }
            }
        }
        .task(id: icon) {
            guard case .file(let path) = icon, fileImage == nil else { return }
            fileImage = await IconCache.loadAsync(forFile: path)
        }
    }
}
