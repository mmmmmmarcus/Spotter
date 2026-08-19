import AppKit
import SwiftUI

/// The two capture pointers, rendered once from SF Symbols and shared by every selection panel.
@MainActor
enum ScreenshotCursor {
    static let pointSize: CGFloat = 24
    static let weight: NSFont.Weight = .medium
    static let outlineWidth: CGFloat = 1
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let shadowBlur: CGFloat = 2
    /// Offsets on a circle of `outlineWidth` dilate the glyph into an even outer border.
    private static let outlineSteps = 24

    static let region = make(symbolName: "dot.crosshair")
    static let window = make(symbolName: "camera.viewfinder")

    private static func make(symbolName: String) -> NSCursor {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        else { return .crosshair }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let artwork = outlined(
            fill: tinted(symbol, configuration, Theme.Colors.screenshotCrosshairFill),
            outline: tinted(symbol, configuration, Theme.Colors.screenshotCrosshairOutline))
        let image = shadowed(artwork)
        return NSCursor(
            image: image,
            hotSpot: CGPoint(x: image.size.width / 2, y: image.size.height / 2))
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
