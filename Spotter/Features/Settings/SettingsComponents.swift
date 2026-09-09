import SwiftUI

/// Reusable building blocks for the Settings window; all metrics come from `Theme` so Settings shares one vocabulary with the palette.

// MARK: - Pane scaffold

/// Standard layout for a settings pane (title header, then scrollable content) so headers, insets and scroll behaviour stay identical across the app.
struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                SettingsHeader(title: title)
                content
            }
            // Ignore the transparent-titlebar safe area and use one fixed `xxl` inset every side instead (the titlebar band is taller than the rhythm we want; traffic lights sit over the sidebar, so nothing collides).
            .padding(Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Settings use the native thin overlay scroller (not the palette's SwiftUI `thinScrollbar`), matching the other windowed setting lists.
            .overlayScroller()
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The title block at the top of every pane. The sidebar already names the pane, so nothing under it restates what the pane is for.
struct SettingsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
    }
}

// MARK: - Grouped card

/// A rounded, hairline-bordered container grouping related rows — the macOS System Settings "card" (rows split by inset dividers via `SettingsRow`/`SettingsDivider`).
struct SettingsCard<Content: View>: View {
    var header: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let header {
                Text(header)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.Spacing.xs)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
        }
    }
}

/// Inset divider between rows inside a `SettingsCard`, aligned under the row's title.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.xl)
    }
}

// MARK: - Row

/// A single settings line (title with optional status subtitle, trailing control); fixed vertical rhythm keeps every card aligned regardless of the control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    /// Reserved for copy that *reports* — a version, a timestamp, a count, a granted state, a path, an error. Never a description of what the row is.
    var subtitle: String? = nil
    /// Optional state indicator rendered after the title (green = active, orange = attention).
    var statusDot: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title)
                        .font(.body)
                    if let statusDot {
                        Circle()
                            .fill(statusDot)
                            .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

// MARK: - Callout

/// A tinted inset box for a notice or warning inside a `SettingsCard` — title + optional message, with an optional trailing control (e.g. a fix-it button). `tint` is the box's colour, not a glyph's.
struct SettingsCallout<Trailing: View>: View {
    let title: String
    var message: String? = nil
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title).font(.body)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

extension SettingsCallout where Trailing == EmptyView {
    init(title: String, message: String? = nil, tint: Color = .secondary) {
        self.init(title: title, message: message, tint: tint) { EmptyView() }
    }
}
