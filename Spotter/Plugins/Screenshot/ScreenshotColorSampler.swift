import CoreGraphics
import Foundation

/// Reads the pixel at the centre of a capture and names it as a hex value. Pure pixel code so the
/// standalone harness can pin it.
enum ScreenshotColorSampler {
    /// Uppercase `#RRGGBB` for the centre pixel, converted to sRGB first — a raw byte read off a
    /// Display-P3 capture would name a colour every other app renders differently.
    static func hexColor(from image: CGImage) -> String? {
        guard image.width > 0, image.height > 0,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Drawn at native size with no resampling, so the centre pixel is the captured one.
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let offset = (image.height / 2) * context.bytesPerRow + (image.width / 2) * 4
        let red = data.load(fromByteOffset: offset, as: UInt8.self)
        let green = data.load(fromByteOffset: offset + 1, as: UInt8.self)
        let blue = data.load(fromByteOffset: offset + 2, as: UInt8.self)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
