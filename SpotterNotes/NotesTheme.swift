import SwiftUI
import UIKit

/// The single place iOS colours and metrics live. `Core/Theme.swift` is AppKit-bound, so this target keeps its own tokens; the tint ramp repeats the Mac's stops value for value.
enum NotesTheme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 10
        static let checkbox: CGFloat = 4
    }

    enum Size {
        static let accessoryBar: CGFloat = 46
        static let accessoryButton: CGFloat = 44
        static let listMarker: CGFloat = 28
        static let tintDot: CGFloat = 10
        /// A todo box is body-text sized, far under a fingertip; the tap target grows by this much on every side.
        static let checkboxTapSlop: CGFloat = 12
    }

    enum Colors {
        static let separator = adaptive(dark: UIColor(white: 1, alpha: 0.10), light: UIColor(white: 0, alpha: 0.12))
        static let controlSurface = adaptive(dark: UIColor(white: 1, alpha: 0.10), light: UIColor(white: 0, alpha: 0.08))
        static let border = adaptive(dark: UIColor(white: 1, alpha: 0.20), light: UIColor(white: 0, alpha: 0.18))
        /// The tick inside a filled todo box, which sits on an accent fill in either appearance.
        static let checkmark = adaptive(dark: UIColor(white: 1, alpha: 1), light: UIColor(white: 1, alpha: 1))

        static func tintAccent(_ tint: NoteTint) -> UIColor {
            adaptive(dark: darkTint(tint), light: lightTint(tint))
        }

        /// The film a tint lays over the editor, at the Mac's two strengths.
        static func tintWash(_ tint: NoteTint) -> UIColor {
            adaptive(
                dark: darkTint(tint).withAlphaComponent(0.24),
                light: lightTint(tint).withAlphaComponent(0.16))
        }

        private static func darkTint(_ tint: NoteTint) -> UIColor {
            switch tint {
            case .red: UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)
            case .orange: UIColor(red: 1.00, green: 0.62, blue: 0.31, alpha: 1)
            case .yellow: UIColor(red: 1.00, green: 0.83, blue: 0.35, alpha: 1)
            case .green: UIColor(red: 0.45, green: 0.83, blue: 0.47, alpha: 1)
            case .mint: UIColor(red: 0.36, green: 0.85, blue: 0.78, alpha: 1)
            case .blue: UIColor(red: 0.40, green: 0.68, blue: 1.00, alpha: 1)
            case .purple: UIColor(red: 0.70, green: 0.55, blue: 1.00, alpha: 1)
            case .pink: UIColor(red: 1.00, green: 0.51, blue: 0.72, alpha: 1)
            case .graphite: UIColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1)
            }
        }

        private static func lightTint(_ tint: NoteTint) -> UIColor {
            switch tint {
            case .red: UIColor(red: 0.85, green: 0.22, blue: 0.24, alpha: 1)
            case .orange: UIColor(red: 0.85, green: 0.45, blue: 0.09, alpha: 1)
            case .yellow: UIColor(red: 0.76, green: 0.58, blue: 0.05, alpha: 1)
            case .green: UIColor(red: 0.20, green: 0.60, blue: 0.27, alpha: 1)
            case .mint: UIColor(red: 0.10, green: 0.60, blue: 0.55, alpha: 1)
            case .blue: UIColor(red: 0.11, green: 0.44, blue: 0.85, alpha: 1)
            case .purple: UIColor(red: 0.47, green: 0.31, blue: 0.85, alpha: 1)
            case .pink: UIColor(red: 0.83, green: 0.26, blue: 0.50, alpha: 1)
            case .graphite: UIColor(red: 0.36, green: 0.39, blue: 0.44, alpha: 1)
            }
        }

        /// Resolved per appearance by UIKit, so no view branches on the colour scheme.
        private static func adaptive(dark: UIColor, light: UIColor) -> UIColor {
            UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        }
    }

    @MainActor
    enum Fonts {
        static var body: UIFont { .preferredFont(forTextStyle: .body) }

        static var monospaced: UIFont {
            .monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
        }

        /// Collapses hidden Markdown syntax to no visible width.
        static let concealed = UIFont.systemFont(ofSize: 0.1)

        static func body(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
            styled(body, traits)
        }

        /// A touch hierarchy: H1 reads as the note's title, H3 only just outgrows the body, deeper levels take weight alone.
        static func heading(level: Int) -> UIFont {
            switch level {
            case 1: styled(.preferredFont(forTextStyle: .title1), .traitBold)
            case 2: styled(.preferredFont(forTextStyle: .title2), .traitBold)
            case 3: styled(.preferredFont(forTextStyle: .title3), .traitBold)
            default: .preferredFont(forTextStyle: .headline)
            }
        }

        private static func styled(_ font: UIFont, _ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
            font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) } ?? font
        }
    }
}
