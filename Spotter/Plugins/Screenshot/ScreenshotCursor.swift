import AppKit
import SwiftUI

/// One pointer per capture mode, rendered once from SF Symbols and shared by every selection panel.
/// Switching mode swaps the pointer outright — the symbol is the mode indicator, so it has to be
/// legible the instant the key lands rather than resolving through a transition.
@MainActor
enum ScreenshotCursor {
    static let pointSize: CGFloat = 24
    static let weight: NSFont.Weight = .medium
    static let outlineWidth: CGFloat = 1
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let shadowBlur: CGFloat = 2
    /// Offsets on a circle of `outlineWidth` dilate the glyph into an even outer border.
    private static let outlineSteps = 24

    static let region = cursor(from: regionArtwork)
    static let window = cursor(from: windowArtwork)
    static let screen = cursor(from: screenArtwork)
    static let text = cursor(from: textArtwork)

    private static let regionArtwork = artwork(symbolName: "dot.crosshair")
    private static let windowArtwork = artwork(symbolName: "camera.fill")
    private static let screenArtwork = artwork(symbolName: "display")
    /// The same crosshair as a region drag, in orange: text recognition is still a region drag, so
    /// only the colour changes. The pointer is the only thing on screen saying the result will be
    /// text rather than a picture.
    private static let textArtwork = artwork(
        symbolName: "dot.crosshair", fill: Theme.Colors.screenshotCrosshairTextFill)

    static func cursor(for mode: ScreenshotCaptureMode) -> NSCursor {
        switch mode {
        case .region: region
        case .window: window
        case .screen: screen
        case .text: text
        }
    }

    private static func cursor(from artwork: NSImage?) -> NSCursor {
        guard let artwork else { return .crosshair }
        return NSCursor(
            image: artwork,
            hotSpot: CGPoint(x: artwork.size.width / 2, y: artwork.size.height / 2))
    }

    private static func artwork(
        symbolName: String, fill: Color = Theme.Colors.screenshotCrosshairFill
    ) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return shadowed(
            outlined(
                fill: tinted(symbol, configuration, fill),
                outline: tinted(symbol, configuration, Theme.Colors.screenshotCrosshairOutline)))
    }

    private static func tinted(
        _ symbol: NSImage, _ configuration: NSImage.SymbolConfiguration, _ color: Color
    ) -> NSImage {
        let palette = NSImage.SymbolConfiguration(paletteColors: [NSColor(color)])
        return symbol.withSymbolConfiguration(configuration.applying(palette)) ?? symbol
    }

    private static func outlined(fill: NSImage, outline: NSImage) -> NSImage {
        let body = CGRect(
            origin: CGPoint(x: outlineWidth, y: outlineWidth), size: fill.size)
        let size = CGSize(
            width: (fill.size.width + outlineWidth * 2).rounded(.up),
            height: (fill.size.height + outlineWidth * 2).rounded(.up))
        return NSImage(size: size, flipped: false) { _ in
            for step in 0..<outlineSteps {
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(outlineSteps)
                outline.draw(
                    in: body.offsetBy(
                        dx: cos(angle) * outlineWidth, dy: sin(angle) * outlineWidth))
            }
            fill.draw(in: body)
            return true
        }
    }

    private static func shadowed(_ artwork: NSImage) -> NSImage {
        let padding = (shadowBlur + abs(shadowOffset.height)).rounded(.up)
        let size = CGSize(
            width: artwork.size.width + padding * 2, height: artwork.size.height + padding * 2)
        return NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            context.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: shadowOffset.width, height: shadowOffset.height)
            shadow.shadowBlurRadius = shadowBlur
            shadow.shadowColor = NSColor(Theme.Colors.screenshotCrosshairShadow)
            shadow.set()
            artwork.draw(
                in: CGRect(origin: CGPoint(x: padding, y: padding), size: artwork.size))
            context.restoreGraphicsState()
            return true
        }
    }
}
