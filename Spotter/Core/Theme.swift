import AppKit
import SwiftUI

/// Central design tokens for the palette UI (see `docs/ui.md`). Colors are a single alpha ramp
/// mirrored per appearance, so the app follows the system between light and dark.
enum Theme {
    enum Animation {
        static let quick: TimeInterval = 0.14
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
        /// Calculator answer card's roomier vertical breathing room.
        static let xxxl: CGFloat = 28
        /// Gap under a category header before its first row; shared by every palette list's `SectionHeader` (launcher, clipboard, emoji, calculator history).
        static let sectionHeaderBottom: CGFloat = 4
        /// Space above a category header (every header except the list's first), which reads as bottom padding closing the previous section — shared by every palette list.
        static let sectionSpacing: CGFloat = 12
    }

    enum Radius {
        static let panel: CGFloat = 26
        static let noteWindow: CGFloat = 20
        static let row: CGFloat = 10
        static let menu: CGFloat = 6
        /// Hover highlight behind a popover menu row.
        static let menuRow: CGFloat = 10
        static let menuPanel: CGFloat = 16
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 10
        static let keyCap: CGFloat = 6
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 4
        /// The user chat bubble — rounder than a row, iMessage-adjacent.
        static let chatBubble: CGFloat = 14
    }

    enum Size {
        static let panelWidth: CGFloat = 750
        static let panelHeight: CGFloat = 475
        /// Fraction of the active screen's visible height between the top of the visible area and the palette's top edge; the window grows downward from this edge (Spotlight-style upper placement).
        static let paletteTopMarginFraction: CGFloat = 0.18
        static let headerHeight: CGFloat = 44
        /// Fixed slot for the header leading glyph (search / back chevron / mode icon) so the search field starts at the same x in every mode — glyphs have different intrinsic widths (chevron 14, magnifyingglass 22). Sized to the magnifyingglass so the launcher spacing is unchanged.
        static let headerIconSlot: CGFloat = 22
        /// Vertical breathing room above the search row — constant across compact/expanded so the bar never shifts when typing flips the state; also the compact bar's symmetric top/bottom slack.
        static let headerPadding: CGFloat = 10
        /// Collapsed compact bar: the search row centered in symmetric `headerPadding` slack.
        static let compactHeight: CGFloat = headerHeight + headerPadding * 2
        static let bottomBarHeight: CGFloat = 52
        static let rowIcon: CGFloat = 24
        static let backgroundTaskProgressWidth: CGFloat = 96
        static let keyCap: CGFloat = 18
        /// Settings shortcut-recorder keycap — smaller than the palette's `keyCap` chip.
        static let recorderKeyCap: CGFloat = 16
        static let menuButton: CGFloat = 36
        static let clipboardListWidth: CGFloat = 290
        static let emojiCell: CGFloat = 56
        /// Empty-launcher dashboard cards share one compact height; the analog clock card is this square.
        static let launcherDashboardHeight: CGFloat = 116
        static let menuWidth: CGFloat = 276
        /// Square slot for a popover-menu row's leading glyph. 20 (not the 16 the artwork suggests) because an `IconCache` app icon only paints ~85% of its canvas: at 20 its visible artwork is 17pt, matching the 17–18pt a `.body` SF Symbol renders at, so symbol and app-icon rows read the same size.
        static let menuIcon: CGFloat = 20
        /// Settings window: wider content area keeps descriptive row text readable beside trailing controls.
        static let settingsWindowWidth: CGFloat = 860
        static let settingsWindowHeight: CGFloat = 550
        /// Settings sidebar column width and the small icon used in setting rows.
        static let settingsSidebar: CGFloat = 184
        static let settingsRowIcon: CGFloat = 20
        static let textReplacementPrefixFieldWidth: CGFloat = 80
        static let textReplacementEditorWidth: CGFloat = 480
        static let textReplacementEditorHeight: CGFloat = 120
        static let noteWindowWidth: CGFloat = 440
        static let noteWindowMinimumWidth: CGFloat = 360
        static let noteListWindowHeight: CGFloat = 500
        static let noteListTopInset: CGFloat = 84
        static let noteToolbarHeight: CGFloat = 32
        static let noteToolbarTitleInset: CGFloat = 112
        /// Little state indicator dot next to a settings row title (Hyper Key active/needs-permission).
        static let statusDot: CGFloat = 6
        /// Gap between the bottom of the visible screen and the command HUD, clearing the Dock.
        static let hudBottomMargin: CGFloat = 120
        /// The in-palette confirmation card's width cap.
        static let confirmationWidth: CGFloat = 380
        /// Minimum empty space to a user chat bubble's left, so it reads as a bubble, not a bar.
        static let chatBubbleInset: CGFloat = 120
    }

    /// System text styles (not hardcoded sizes) so the UI honors Dynamic Type.
    enum Typography {
        static let searchField = Font.system(size: 20, weight: .regular)
        static let headerIcon = Font.system(size: 18, weight: .medium)
        static let rowTitle = Font.body
        static let rowTrailing = Font.callout
        static let sectionHeader = Font.subheadline.weight(.medium)
        /// The big value line on the calculator answer card (both source and target sides).
        static let calcResult = Font.title
        static let keyCap = Font.caption
        static let bar = Font.callout.weight(.medium)
        static let menuRow = Font.body
        static let menuShortcut = Font.callout
        static let menuIcon = Font.body
    }

    /// One alpha ramp, mirrored per appearance: white over the dark surface, black over the light one.
    /// Black at the same alpha reads heavier than white, so the light stops are not a straight flip.
    enum Colors {
        /// The scrim laid over the behind-window material to make the panel surface. Dark dims it;
        /// light brightens it, so both keep the desktop showing through rather than turning opaque.
        static let panelScrim = adaptive(dark: .black.opacity(0.40), light: .white.opacity(0.55))
        /// Selection fill: a soft neutral translucent layer shared by launcher and clipboard so both lists look identical.
        static let selection = adaptive(dark: .white.opacity(0.10), light: .black.opacity(0.08))
        /// Mouse hover — a fainter layer that follows the cursor, visually distinct from selection.
        static let rowHover = adaptive(dark: .white.opacity(0.05), light: .black.opacity(0.04))
        static let menuHover = adaptive(dark: .white.opacity(0.10), light: .black.opacity(0.08))
        static let separator = adaptive(dark: .white.opacity(0.10), light: .black.opacity(0.12))
        /// Small control surfaces: kbd chips, glyph tiles.
        static let controlSurface = adaptive(dark: .white.opacity(0.10), light: .black.opacity(0.08))
        /// Control borders: outlined kbd chips.
        static let border = adaptive(dark: .white.opacity(0.20), light: .black.opacity(0.18))
        static let textSecondary = adaptive(dark: .white.opacity(0.60), light: .black.opacity(0.62))
        static let textTertiary = adaptive(dark: .white.opacity(0.40), light: .black.opacity(0.42))
        /// Settings grouped "card": a faint raised surface whose hairline border doubles as the inset row divider.
        static let cardFill = adaptive(dark: .white.opacity(0.05), light: .black.opacity(0.035))
        static let cardStroke = adaptive(dark: .white.opacity(0.10), light: .black.opacity(0.10))
        /// Placeholder tile held while a row's icon decodes, and the Onboarding surface glow.
        static let surfaceGlow = adaptive(dark: .white.opacity(0.06), light: .black.opacity(0.05))
        /// Tint layered into the Liquid Glass floating controls (action group + menu circle) so the
        /// glass reads frosted rather than clear. White in both appearances — it brightens the glass,
        /// and a dark tint over light glass would read as a shadow instead of frost.
        static let glassFrost = adaptive(dark: .white.opacity(0.05), light: .white.opacity(0.30))
        /// The violet of the app mark. The one hue in the system: the About support callout's tint and the dashboard clock's second hand.
        static let brand = Color(red: 0.525, green: 0.231, blue: 1.0)

        /// Resolved per appearance by AppKit, so every call site stays a plain `Color` and the whole
        /// app follows the system without a single `colorScheme` check in a view body.
        private static func adaptive(dark: Color, light: Color) -> Color {
            Color(nsColor: NSColor(name: nil) { NSColor($0.isDark ? dark : light) })
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// A single keycap chip: `.outline` for hotkey hints on rows, `.filled` for footer shortcuts.
struct KeyCapChip: View {
    enum Style {
        case outline
        case filled
    }

    let text: String
    var style: Style = .filled

    /// "↵" is absent from SF Pro and falls back to Lucida Grande UI, which seats it 1.1pt higher in the line box than the SF caps — visibly top-heavy in a chip. Nudging via `offset` is render-only, so the chip keeps the same footprint as every other cap.
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
        Text(text)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: Theme.Size.keyCap, minHeight: Theme.Size.keyCap)
            .background {
                switch style {
                case .filled: shape.fill(Theme.Colors.controlSurface)
                case .outline: shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// A floating Liquid Glass control surface (action group + menu button), interactive for native lensing with a whitish frost tint so it reads brighter than clear glass.
    func frosted(in shape: some Shape) -> some View {
        glassEffect(.regular.interactive().tint(Theme.Colors.glassFrost), in: shape)
            .tint(.clear)
    }
}
