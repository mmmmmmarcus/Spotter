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

    static let screenshot = cursor(from: screenshotArtwork)
    static let ocr = cursor(from: ocrArtwork)
    static let colorPicker = cursor(from: colorPickerArtwork, hotSpotAtTip: true)

    private static let screenshotArtwork = artwork(symbolName: "dot.crosshair")
    /// The same crosshair as a region drag, in orange: OCR is still a region drag, so only the
    /// colour changes. The pointer is the only thing on screen saying the result will be text
    /// rather than a picture.
    private static let ocrArtwork = artwork(
        symbolName: "dot.crosshair", fill: Theme.Colors.screenshotCrosshairTextFill)
    private static let colorPickerArtwork = artwork(symbolName: "eyedropper")

    static func cursor(for mode: ScreenshotCaptureMode) -> NSCursor {
        switch mode {
        case .screenshot: screenshot
        case .ocr: ocr
        case .colorPicker: colorPicker
        }
    }

    private static func cursor(from artwork: NSImage?, hotSpotAtTip: Bool = false) -> NSCursor {
        guard let artwork else { return .crosshair }
        let center = CGPoint(x: artwork.size.width / 2, y: artwork.size.height / 2)
        return NSCursor(
            image: artwork,
            hotSpot: hotSpotAtTip ? tipHotSpot(of: artwork) ?? center : center)
    }

    /// An eyedropper samples at its tip, so its hotspot is the ink pixel nearest the artwork's
    /// bottom-left corner rather than the canvas centre. Scanning the rasterized artwork survives
    /// any SF Symbol redraw; the soft shadow stays below the solid-ink alpha threshold.
    private static func tipHotSpot(of artwork: NSImage) -> CGPoint? {
        let width = Int(artwork.size.width.rounded()), height = Int(artwork.size.height.rounded())
        guard width > 0, height > 0,
            let cgImage = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        var tip: (score: Int, x: Int, row: Int)?
        for row in 0..<height {
            for x in 0..<width {
                let alpha = data.load(fromByteOffset: row * context.bytesPerRow + x * 4 + 3, as: UInt8.self)
                guard alpha >= 128 else { continue }
                // Memory row 0 is the top, so the bottom-left corner minimizes both terms.
                let score = x + (height - 1 - row)
                if tip == nil || score < tip!.score { tip = (score, x, row) }
            }
        }
        // NSCursor hotspots use a top-left origin, matching the memory row directly.
        return tip.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.row)) }
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
