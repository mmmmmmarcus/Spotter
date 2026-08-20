import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pure pixel processing for the clipboard payload; it never reads the screen, pasteboard or disk.
enum ScreenshotImageProcessor {
    static func applyingRoundedCorners(to image: CGImage) -> CGImage? {
        let size = CGSize(width: image.width, height: image.height)
        let radius = ScreenshotGeometry.roundedCornerRadius(forPixelSize: size)
        guard radius > 0 else { return image }

        let bounds = CGRect(origin: .zero, size: size)
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setShouldAntialias(true)
        context.addPath(
            CGPath(
                roundedRect: bounds,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil))
        context.clip()
        context.draw(image, in: bounds)
        return context.makeImage()
    }

    static func tiffData(from image: CGImage, roundedCorners: Bool) -> Data? {
        encoded(image, roundedCorners: roundedCorners, type: UTType.tiff)
    }

    /// The editor's Save output; PNG keeps the rounded corners' transparency on disk.
    static func pngData(from image: CGImage, roundedCorners: Bool) -> Data? {
        encoded(image, roundedCorners: roundedCorners, type: UTType.png)
    }

    private static func encoded(
        _ image: CGImage, roundedCorners: Bool, type: UTType
    ) -> Data? {
        let output: CGImage
        if roundedCorners {
            guard let rounded = applyingRoundedCorners(to: image) else { return nil }
            output = rounded
        } else {
            output = image
        }

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
