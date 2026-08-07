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

        check("dark appearance reports isDark", NSAppearance(named: .darkAqua)!.isDark)
        check("light appearance does not", !NSAppearance(named: .aqua)!.isDark)

        print(failures == 0 ? "\nTheme: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
