import AppKit
import SwiftUI

/// Guards the appearance ramp in `Theme.Colors`: every surface token has to resolve differently in
/// light and dark, and the dark stops must stay exactly where they were before light mode existed —
/// a regression there restyles the shipped look by accident.
@main
struct ThemeTests {
    @MainActor
    static func main() {
        var failures = 0

        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        func resolve(_ color: Color, _ name: NSAppearance.Name) -> (
            r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
        ) {
            var out: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let c = NSColor(color).usingColorSpace(.deviceRGB)!
                out = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
            }
            return out
        }

        func check(
            _ name: String, _ color: Color,
            darkWhite: Bool, darkAlpha: CGFloat, lightWhite: Bool, lightAlpha: CGFloat
        ) {
            let dark = resolve(color, .darkAqua)
            let light = resolve(color, .aqua)
            check(
                "\(name) is \(darkWhite ? "white" : "black") \(darkAlpha) in dark",
                dark.r == (darkWhite ? 1 : 0) && abs(dark.a - darkAlpha) < 0.001)
            check(
                "\(name) is \(lightWhite ? "white" : "black") \(lightAlpha) in light",
                light.r == (lightWhite ? 1 : 0) && abs(light.a - lightAlpha) < 0.001)
        }

        // Dark stops are the pre-light-mode values, verbatim.
        check(
            "panelScrim", Theme.Colors.panelScrim,
            darkWhite: false, darkAlpha: 0.40, lightWhite: true, lightAlpha: 0.55)
        check(
            "selection", Theme.Colors.selection,
            darkWhite: true, darkAlpha: 0.10, lightWhite: false, lightAlpha: 0.08)
        check(
            "rowHover", Theme.Colors.rowHover,
            darkWhite: true, darkAlpha: 0.05, lightWhite: false, lightAlpha: 0.04)
        check(
            "menuHover", Theme.Colors.menuHover,
            darkWhite: true, darkAlpha: 0.10, lightWhite: false, lightAlpha: 0.08)
        check(
            "separator", Theme.Colors.separator,
            darkWhite: true, darkAlpha: 0.10, lightWhite: false, lightAlpha: 0.12)
        check(
            "controlSurface", Theme.Colors.controlSurface,
            darkWhite: true, darkAlpha: 0.10, lightWhite: false, lightAlpha: 0.08)
        check(
            "border", Theme.Colors.border,
            darkWhite: true, darkAlpha: 0.20, lightWhite: false, lightAlpha: 0.18)
        check(
            "textSecondary", Theme.Colors.textSecondary,
            darkWhite: true, darkAlpha: 0.60, lightWhite: false, lightAlpha: 0.62)
        check(
            "textTertiary", Theme.Colors.textTertiary,
            darkWhite: true, darkAlpha: 0.40, lightWhite: false, lightAlpha: 0.42)
        check(
            "cardStroke", Theme.Colors.cardStroke,
            darkWhite: true, darkAlpha: 0.10, lightWhite: false, lightAlpha: 0.10)
        check(
            "surfaceGlow", Theme.Colors.surfaceGlow,
            darkWhite: true, darkAlpha: 0.06, lightWhite: false, lightAlpha: 0.05)
        // The one token that stays white in both: frost brightens glass, a dark tint would shadow it.
        check(
            "glassFrost", Theme.Colors.glassFrost,
            darkWhite: true, darkAlpha: 0.05, lightWhite: true, lightAlpha: 0.30)
        check(
            "screenshotSelectionBorder", Theme.Colors.screenshotSelectionBorder,
            darkWhite: true, darkAlpha: 1.0, lightWhite: false, lightAlpha: 1.0)
        check(
            "screenshotHitSurface", Theme.Colors.screenshotHitSurface,
            darkWhite: false, darkAlpha: 1.0 / 255.0,
            lightWhite: false, lightAlpha: 1.0 / 255.0)
        check(
            "screenshotSelectionOverlay", Theme.Colors.screenshotSelectionOverlay,
            darkWhite: true, darkAlpha: 0.05, lightWhite: false, lightAlpha: 0.05)
        let textDark = resolve(Theme.Colors.screenshotCrosshairTextFill, .darkAqua)
        let textLight = resolve(Theme.Colors.screenshotCrosshairTextFill, .aqua)
        let cursorOrange = (CGFloat(1.0), CGFloat(149.0 / 255.0), CGFloat(0.0))
        check(
            "screenshotCrosshairTextFill keeps the OCR-cursor orange in dark",
            abs(textDark.r - cursorOrange.0) < 0.001
                && abs(textDark.g - cursorOrange.1) < 0.001
                && abs(textDark.b - cursorOrange.2) < 0.001
                && textDark.a == 1)
        check(
            "screenshotCrosshairTextFill keeps the OCR-cursor orange in light",
            abs(textLight.r - cursorOrange.0) < 0.001
                && abs(textLight.g - cursorOrange.1) < 0.001
                && abs(textLight.b - cursorOrange.2) < 0.001
                && textLight.a == 1)

        let crosshairDark = resolve(Theme.Colors.screenshotCrosshairFill, .darkAqua)
        let crosshairLight = resolve(Theme.Colors.screenshotCrosshairFill, .aqua)
        let crosshairBlue = (CGFloat(32.0 / 255.0), CGFloat(118.0 / 255.0), CGFloat(1.0))
        check(
            "screenshotCrosshairFill keeps the capture-cursor blue in dark",
            abs(crosshairDark.r - crosshairBlue.0) < 0.001
                && abs(crosshairDark.g - crosshairBlue.1) < 0.001
                && abs(crosshairDark.b - crosshairBlue.2) < 0.001
                && crosshairDark.a == 1)
        check(
            "screenshotCrosshairFill keeps the capture-cursor blue in light",
            abs(crosshairLight.r - crosshairBlue.0) < 0.001
                && abs(crosshairLight.g - crosshairBlue.1) < 0.001
                && abs(crosshairLight.b - crosshairBlue.2) < 0.001
                && crosshairLight.a == 1)
        check(
            "screenshotCrosshairOutline", Theme.Colors.screenshotCrosshairOutline,
            darkWhite: true, darkAlpha: 1.0, lightWhite: true, lightAlpha: 1.0)
        check(
            "screenshotCrosshairShadow", Theme.Colors.screenshotCrosshairShadow,
            darkWhite: false, darkAlpha: 0.28, lightWhite: false, lightAlpha: 0.28)

        // Selection must always beat hover, in both appearances — the shared row `fill` precedence
        // is meaningless if the two read the same weight.
        for (label, name) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let selection = resolve(Theme.Colors.selection, name)
            let hover = resolve(Theme.Colors.rowHover, name)
            check("selection outweighs hover in \(label)", selection.a > hover.a)
        }

        // The brand violet is the one hue, and it does not shift with appearance.
        check(
            "brand stays fixed across appearances",
            resolve(Theme.Colors.brand, .darkAqua) == resolve(Theme.Colors.brand, .aqua))

        // The Notes tint ramp: every tint carries a distinct pair of stops, and its wash stays far
        // enough under the swatch that editor text never has to compete with it.
        for tint in NoteTint.allCases {
            let accentDark = resolve(Theme.Colors.noteTintAccent(tint), .darkAqua)
            let accentLight = resolve(Theme.Colors.noteTintAccent(tint), .aqua)
            check(
                "\(tint.rawValue) accent is opaque in both appearances",
                accentDark.a == 1 && accentLight.a == 1)
            check(
                "\(tint.rawValue) accent takes a deeper stop in light",
                accentDark.r + accentDark.g + accentDark.b > accentLight.r + accentLight.g
                    + accentLight.b)
            let washDark = resolve(Theme.Colors.noteTintWash(tint), .darkAqua)
            let washLight = resolve(Theme.Colors.noteTintWash(tint), .aqua)
            check(
                "\(tint.rawValue) wash stays faint",
                abs(washDark.a - 0.24) < 0.001 && abs(washLight.a - 0.16) < 0.001)
            check(
                "\(tint.rawValue) wash keeps its accent hue",
                abs(washDark.r - accentDark.r) < 0.001 && abs(washLight.r - accentLight.r) < 0.001)
        }
        check(
            "no two tints share a dark stop",
            Set(
                NoteTint.allCases.map {
                    let c = resolve(Theme.Colors.noteTintAccent($0), .darkAqua)
                    return "\(c.r)-\(c.g)-\(c.b)"
                }
            ).count == NoteTint.allCases.count)

        check("dark appearance reports isDark", NSAppearance(named: .darkAqua)!.isDark)
        check("light appearance does not", !NSAppearance(named: .aqua)!.isDark)
        check("a transparent plugin window keeps its 20-point radius", Theme.Radius.window == 20)

        print(failures == 0 ? "\nTheme: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
