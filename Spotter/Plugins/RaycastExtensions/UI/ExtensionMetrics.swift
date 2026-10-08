import SwiftUI

/// `Theme`'s palette geometry at the user's Interface Size; `.standard` is `Theme` verbatim.
struct ExtensionMetrics: Equatable, Sendable {
    static let standard = ExtensionMetrics(scale: 1)

    let scale: CGFloat

    var spacing: Spacing { Spacing(scale: scale) }
    var radius: Radius { Radius(scale: scale) }
    var size: Size { Size(scale: scale) }
    var typography: Typography { Typography(scale: scale) }

    /// For a tuned length a surface owns itself, where `Theme` states no token for it.
    func scaled(_ value: CGFloat) -> CGFloat { scaledPoints(value, scale) }

    struct Spacing: Equatable, Sendable {
        let scale: CGFloat

        var xxs: CGFloat { scaledPoints(Theme.Raycast.Spacing.xxs, scale) }
        var xs: CGFloat { scaledPoints(Theme.Raycast.Spacing.xs, scale) }
        var sm: CGFloat { scaledPoints(Theme.Raycast.Spacing.sm, scale) }
        var md: CGFloat { scaledPoints(Theme.Raycast.Spacing.md, scale) }
        var lg: CGFloat { scaledPoints(Theme.Raycast.Spacing.lg, scale) }
        var xl: CGFloat { scaledPoints(Theme.Raycast.Spacing.xl, scale) }
        var dialogInset: CGFloat { scaledPoints(Theme.Raycast.Spacing.dialogInset, scale) }
        var xxl: CGFloat { scaledPoints(Theme.Raycast.Spacing.xxl, scale) }
        var xxxl: CGFloat { scaledPoints(Theme.Raycast.Spacing.xxxl, scale) }
        var sectionHeaderBottom: CGFloat { scaledPoints(Theme.Raycast.Spacing.sectionHeaderBottom, scale) }
        var sectionSpacing: CGFloat { scaledPoints(Theme.Raycast.Spacing.sectionSpacing, scale) }
        var emojiSectionSpacing: CGFloat { scaledPoints(Theme.Raycast.Spacing.emojiSectionSpacing, scale) }
        var chatTranscriptBottom: CGFloat { scaledPoints(Theme.Raycast.Spacing.chatTranscriptBottom, scale) }
        var chatFollowTailSlack: CGFloat { scaledPoints(Theme.Raycast.Spacing.chatFollowTailSlack, scale) }
        var chatLine: CGFloat { scaledPoints(Theme.Raycast.Spacing.chatLine, scale) }
    }

    struct Radius: Equatable, Sendable {
        let scale: CGFloat

        var panel: CGFloat { scaledPoints(Theme.Raycast.Radius.panel, scale) }
        var row: CGFloat { scaledPoints(Theme.Raycast.Radius.row, scale) }
        var emojiCell: CGFloat { scaledPoints(Theme.Raycast.Radius.emojiCell, scale) }
        var menu: CGFloat { scaledPoints(Theme.Raycast.Radius.menu, scale) }
        var menuRow: CGFloat { scaledPoints(Theme.Raycast.Radius.menuRow, scale) }
        var barControl: CGFloat { scaledPoints(Theme.Raycast.Radius.barControl, scale) }
        var menuPanel: CGFloat { scaledPoints(Theme.Raycast.Radius.menuPanel, scale) }
        var dialogSymbol: CGFloat { scaledPoints(Theme.Raycast.Radius.dialogSymbol, scale) }
        var dialog: CGFloat { scaledPoints(Theme.Raycast.Radius.dialog, scale) }
        var thumbnail: CGFloat { scaledPoints(Theme.Raycast.Radius.thumbnail, scale) }
        var glyph: CGFloat { scaledPoints(Theme.Raycast.Radius.glyph, scale) }
        var attachmentChip: CGFloat { scaledPoints(Theme.Raycast.Radius.attachmentChip, scale) }
        var card: CGFloat { scaledPoints(Theme.Raycast.Radius.card, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Raycast.Radius.keyCap, scale) }
        var tooltip: CGFloat { scaledPoints(Theme.Raycast.Radius.tooltip, scale) }
    }

    struct Size: Equatable, Sendable {
        let scale: CGFloat

        var panelWidth: CGFloat { scaledPoints(Theme.Raycast.Size.panelWidth, scale) }
        var panelHeight: CGFloat { scaledPoints(Theme.Raycast.Size.panelHeight, scale) }
        var headerHeight: CGFloat { scaledPoints(Theme.Raycast.Size.headerHeight, scale) }
        var headerIconSlot: CGFloat { scaledPoints(Theme.Raycast.Size.headerIconSlot, scale) }
        var searchFieldMinWidth: CGFloat { scaledPoints(Theme.Raycast.Size.searchFieldMinWidth, scale) }
        var headerPadding: CGFloat { scaledPoints(Theme.Raycast.Size.headerPadding, scale) }
        /// Derived, not scaled: the compact bar must stay exactly the header in symmetric slack.
        var compactHeight: CGFloat { headerHeight + headerPadding * 2 }
        var bottomBarHeight: CGFloat { scaledPoints(Theme.Raycast.Size.bottomBarHeight, scale) }
        var barButtonHeight: CGFloat { scaledPoints(Theme.Raycast.Size.barButtonHeight, scale) }
        var rowIcon: CGFloat { scaledPoints(Theme.Raycast.Size.rowIcon, scale) }
        var resultRowIcon: CGFloat { scaledPoints(Theme.Raycast.Size.resultRowIcon, scale) }
        var colorDot: CGFloat { scaledPoints(Theme.Raycast.Size.colorDot, scale) }
        var calendarBarWidth: CGFloat { scaledPoints(Theme.Raycast.Size.calendarBarWidth, scale) }
        var calendarBarHeight: CGFloat { scaledPoints(Theme.Raycast.Size.calendarBarHeight, scale) }
        var keyCap: CGFloat { scaledPoints(Theme.Raycast.Size.keyCap, scale) }
        var compactKeyCap: CGFloat { scaledPoints(Theme.Raycast.Size.compactKeyCap, scale) }
        var heroKeyCap: CGFloat { scaledPoints(Theme.Raycast.Size.heroKeyCap, scale) }
        var menuButton: CGFloat { scaledPoints(Theme.Raycast.Size.menuButton, scale) }
        var checkbox: CGFloat { scaledPoints(Theme.Raycast.Size.checkbox, scale) }

        var menuWidth: CGFloat { scaledPoints(Theme.Raycast.Size.menuWidth, scale) }
        var actionMenuWidth: CGFloat { scaledPoints(Theme.Raycast.Size.actionMenuWidth, scale) }
        var clipboardFilterMenuWidth: CGFloat { scaledPoints(Theme.Raycast.Size.clipboardFilterMenuWidth, scale) }
        var fileSearchFilterMenuWidth: CGFloat { scaledPoints(Theme.Raycast.Size.fileSearchFilterMenuWidth, scale) }
        var emojiCategoryMenuWidth: CGFloat { scaledPoints(Theme.Raycast.Size.emojiCategoryMenuWidth, scale) }
        var menuIcon: CGFloat { scaledPoints(Theme.Raycast.Size.menuIcon, scale) }
        var menuBrandIcon: CGFloat { scaledPoints(Theme.Raycast.Size.menuBrandIcon, scale) }
        var barBrandIcon: CGFloat { scaledPoints(Theme.Raycast.Size.barBrandIcon, scale) }
        var menuRowSpacing: CGFloat { scaledPoints(Theme.Raycast.Size.menuRowSpacing, scale) }
        var menuSectionHeader: CGFloat { scaledPoints(Theme.Raycast.Size.menuSectionHeader, scale) }
        /// Derived like `Theme`'s, so the row cap still counts whole rows at every size.
        var menuRowHeight: CGFloat { menuIcon + Spacing(scale: scale).md * 2 }
        var menuRowsMaxHeight: CGFloat {
            (Theme.Raycast.Size.menuVisibleRows * (menuRowHeight + menuRowSpacing)).rounded()
        }
        var clipboardListWidth: CGFloat { scaledPoints(Theme.Raycast.Size.clipboardListWidth, scale) }
        var clipboardMediaHeight: CGFloat { scaledPoints(Theme.Raycast.Size.clipboardMediaHeight, scale) }
        var clipboardPreviewPixel: CGFloat { scaledPoints(Theme.Raycast.Size.clipboardPreviewPixel, scale) }
        var emojiGridInset: CGFloat { scaledPoints(Theme.Raycast.Size.emojiGridInset, scale) }
        var emojiCell: CGFloat { scaledPoints(Theme.Raycast.Size.emojiCell, scale) }

        var markdownListMarker: CGFloat { scaledPoints(Theme.Raycast.Size.markdownListMarker, scale) }
        var markdownQuoteBar: CGFloat { scaledPoints(Theme.Raycast.Size.markdownQuoteBar, scale) }
        var chatMessageAction: CGFloat { scaledPoints(Theme.Raycast.Size.chatMessageAction, scale) }
        var chatImageThumb: CGFloat { scaledPoints(Theme.Raycast.Size.chatImageThumb, scale) }
        var chatAttachmentGlyph: CGFloat { scaledPoints(Theme.Raycast.Size.chatAttachmentGlyph, scale) }
        var chatAttachmentThumb: CGFloat { scaledPoints(Theme.Raycast.Size.chatAttachmentThumb, scale) }
        var chatAttachmentRemove: CGFloat { scaledPoints(Theme.Raycast.Size.chatAttachmentRemove, scale) }
        var chatAttachmentInset: CGFloat { scaledPoints(Theme.Raycast.Size.chatAttachmentInset, scale) }

        var quickActionPanel: CGFloat { scaledPoints(Theme.Raycast.Size.quickActionPanel, scale) }
        var quickActionHeaderIcon: CGFloat { scaledPoints(Theme.Raycast.Size.quickActionHeaderIcon, scale) }
        var quickActionScrollFade: CGFloat { scaledPoints(Theme.Raycast.Size.quickActionScrollFade, scale) }
        var quickActionPanelBody: CGFloat { scaledPoints(Theme.Raycast.Size.quickActionPanelBody, scale) }
        var quickActionPanelMinBody: CGFloat { scaledPoints(Theme.Raycast.Size.quickActionPanelMinBody, scale) }

        var dialogCompactWidth: CGFloat { scaledPoints(Theme.Raycast.Size.dialogCompactWidth, scale) }
        var dialogWidth: CGFloat { scaledPoints(Theme.Raycast.Size.dialogWidth, scale) }
        var dialogButtonHeight: CGFloat {
            menuButton
                - scaledPoints(Theme.Raycast.Size.menuButton - Theme.Raycast.Size.dialogButtonHeight, scale)
        }
        var dialogSymbol: CGFloat { scaledPoints(Theme.Raycast.Size.dialogSymbol, scale) }
        var dialogSymbolContainer: CGFloat {
            scaledPoints(Theme.Raycast.Size.dialogSymbolContainer, scale)
        }
        var dialogIcon: CGFloat { scaledPoints(Theme.Raycast.Size.dialogIcon, scale) }
        var hudMaxWidth: CGFloat { scaledPoints(Theme.Raycast.Size.hudMaxWidth, scale) }
        var hudWidth: CGFloat { scaledPoints(Theme.Raycast.Size.hudWidth, scale) }
        var hudHeight: CGFloat { scaledPoints(Theme.Raycast.Size.hudHeight, scale) }
        var volumeTrackHeight: CGFloat { scaledPoints(Theme.Raycast.Size.volumeTrackHeight, scale) }
        var volumeReadout: CGFloat { scaledPoints(Theme.Raycast.Size.volumeReadout, scale) }
    }

    /// `NSFont` is the only public source of a text style's size and face.
    struct Typography: Sendable {
        let scale: CGFloat

        var searchFieldSize: CGFloat { scaledPoints(Theme.Raycast.Typography.searchFieldSize, scale) }
        var searchField: Font {
            scale == 1
                ? Theme.Raycast.Typography.searchField
                : .system(size: searchFieldSize, weight: .regular)
        }
        /// Isolated because `Theme`'s twin is, not because resolving a font needs main.
        @MainActor var searchFieldNSFont: NSFont {
            scale == 1
                ? Theme.Raycast.Typography.searchFieldNSFont
                : NSFont.systemFont(ofSize: searchFieldSize, weight: .regular)
        }
        var headerIcon: Font {
            scale == 1
                ? Theme.Raycast.Typography.headerIcon
                : .system(size: scaledPoints(18, scale), weight: .medium)
        }

        var rowTitle: Font { font(Theme.Raycast.Typography.rowTitle, .body) }
        var rowTrailing: Font { font(Theme.Raycast.Typography.rowTrailing, .callout) }
        var sectionHeader: Font { font(Theme.Raycast.Typography.sectionHeader, .subheadline, .medium) }
        var panelTitle: Font { font(Theme.Raycast.Typography.panelTitle, .headline) }
        var calcResult: Font { font(Theme.Raycast.Typography.calcResult, .title1) }
        var keyCap: Font { font(Theme.Raycast.Typography.keyCap, .caption1) }
        var compactKeyCap: Font { font(Theme.Raycast.Typography.compactKeyCap, .caption2) }
        var heroKeyCap: Font { font(Theme.Raycast.Typography.heroKeyCap, .body) }
        var markdownHeading1: Font { font(Theme.Raycast.Typography.markdownHeading1, .title2, .semibold) }
        var markdownHeading2: Font { font(Theme.Raycast.Typography.markdownHeading2, .title3, .semibold) }
        var markdownHeading3: Font { font(Theme.Raycast.Typography.markdownHeading3, .headline) }
        var code: Font {
            scale == 1
                ? Theme.Raycast.Typography.code
                : .system(size: nsFont(.callout).pointSize, design: .monospaced)
        }
        var inlineCode: Font { font(Theme.Raycast.Typography.inlineCode, .body).monospaced() }
        var bar: Font { font(Theme.Raycast.Typography.bar, .callout, .medium) }
        var chip: Font { font(Theme.Raycast.Typography.chip, .callout) }
        @MainActor var chipNSFont: NSFont { scale == 1 ? Theme.Raycast.Typography.chipNSFont : nsFont(.callout) }
        var disclosure: Font { font(Theme.Raycast.Typography.disclosure, .caption1, .semibold) }
        var menuRow: Font { font(Theme.Raycast.Typography.menuRow, .body) }
        var menuShortcut: Font { font(Theme.Raycast.Typography.menuShortcut, .callout) }
        var menuIcon: Font { font(Theme.Raycast.Typography.menuIcon, .body) }

        /// The AppKit twin of a text style, for text an `NSTextView` draws beside SwiftUI's own.
        func textNSFont(
            _ style: NSFont.TextStyle, weight: NSFont.Weight? = nil, monospaced: Bool = false
        ) -> NSFont {
            let base = nsFont(style)
            if monospaced { return .monospacedSystemFont(ofSize: base.pointSize, weight: weight ?? .regular) }
            guard let weight else { return base }
            return .systemFont(ofSize: base.pointSize, weight: weight)
        }

        /// Composed like `Theme`'s own: the style carries the face, an explicit weight overrides it.
        private func font(
            _ base: Font, _ style: NSFont.TextStyle, _ weight: Font.Weight? = nil
        )
            -> Font
        {
            guard scale != 1 else { return base }
            let scaled = Font(nsFont(style))
            return weight.map(scaled.weight) ?? scaled
        }

        /// Its own descriptor, so `.headline` stays Bold and `.caption2` Medium rather than lightening.
        private func nsFont(_ style: NSFont.TextStyle) -> NSFont {
            let base = NSFont.preferredFont(forTextStyle: style)
            guard scale != 1 else { return base }
            return NSFont(descriptor: base.fontDescriptor, size: scaledPoints(base.pointSize, scale)) ?? base
        }
    }
}

/// Whole points: a fractional row pitch lands keycap edges and the dissolve mask off-pixel.
private func scaledPoints(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    scale == 1 ? value : (value * scale).rounded()
}

extension EnvironmentValues {
    /// `.standard` by default, so a shared `DesignSystem` view outside the palette never scales.
    @Entry var metrics = ExtensionMetrics.standard
}
