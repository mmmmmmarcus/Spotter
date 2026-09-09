import SwiftUI

/// Building blocks for the Settings window. The content area is a native grouped `Form`: panes pass
/// `Section`s, and macOS owns the row metrics, typography, separators, group backgrounds, Dynamic
/// Type and the label/control accessibility pairing. Spotter only supplies the pane title, the row's
/// own copy and whatever control the row carries.

// MARK: - Pane scaffold

/// Standard layout for a settings pane: the pane title, then the grouped `Form` holding its sections.
struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: title)
                // `xxl` lines the title up with the leading edge of the Form's own section boxes.
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xxl)
            Form { leadingHeaderStripped }
                .formStyle(.grouped)
                // The Form owns the scroll view, so the probe has to look down into it rather than up.
                .containerOverlayScroller()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The transparent titlebar band is taller than the rhythm we want, and the traffic lights sit over the sidebar, so nothing collides.
        .ignoresSafeArea(edges: .top)
    }

    /// The pane's opening group carries no header: the pane title already names what it opens with,
    /// and a header directly under it reads as the same label twice. Expressed here rather than at
    /// the panes, so a pane added later inherits the rule instead of remembering it — the sections
    /// are decomposed and rebuilt, and only the first one's header is left unbuilt. Panes keep
    /// writing `Section("Header") { … }` exactly as before. Settings sections carry no footers.
    private var leadingHeaderStripped: some View {
        Group(sections: content) { sections in
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index == 0 {
                    Section { section.content }
                } else {
                    Section { section.content } header: { section.header }
                }
            }
        }
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

// MARK: - Row

/// A single settings line inside a `Section`: a `LabeledContent` pairing the title with the row's
/// control, and — only where the copy *reports* something — a caption under both. The pairing is
/// what gives a `labelsHidden` control its accessible name, so the row is read as "title, switch".
struct SettingsRow<Trailing: View>: View {
    let title: String
    /// Reserved for copy that *reports* — a version, a timestamp, a count, a granted state, a path, an error. Never a description of what the row is.
    var subtitle: String? = nil
    /// Optional state indicator rendered after the title (green = active, orange = attention).
    var statusDot: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let subtitle {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                labeled
                // Full row width rather than the label column: several of these are disclosures, and a paragraph folded into half a row reads as a mistake.
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            labeled
        }
    }

    private var labeled: some View {
        LabeledContent {
            trailing
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(title)
                if let statusDot {
                    Circle()
                        .fill(statusDot)
                        .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                }
            }
        }
    }
}

// MARK: - Callout

/// A tinted inset box for a notice or a kept disclosure — title + optional message, with an optional trailing control (e.g. a fix-it button). `tint` is the box's colour, not a glyph's.
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

// MARK: - Card stack

/// The hand-rolled grouped card the two surfaces that are *not* forms still use — About's links and
/// the onboarding steps. Both are bespoke layouts (a hero column, a wizard step) rather than lists of
/// settings, so neither can be a `Form`; keeping their own card here is what lets the Settings panes
/// be native without restyling either one.
struct PanelCard<Content: View>: View {
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

/// Inset divider between rows inside a `PanelCard`, aligned under the row's title.
struct PanelCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.xl)
    }
}

/// One line inside a `PanelCard`, with the fixed rhythm a card has to supply for itself.
struct PanelCardRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title)
                    .font(.body)
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
