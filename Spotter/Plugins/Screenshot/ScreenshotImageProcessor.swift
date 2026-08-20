import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The encoding used when an edited capture is written to disk. The clipboard stays TIFF in both
/// cases: it is lossless and the format every app pastes, and a file-size choice buys nothing there.
enum ScreenshotFileFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg

    var id: String { rawValue }
    var title: String { self == .png ? "PNG" : "JPG" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var contentType: UTType { self == .png ? .png : .jpeg }
    /// JPEG carries no alpha, so a rounded corner would encode as a hard black wedge.
    var preservesTransparency: Bool { self == .png }
}

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

    /// The editor's Save output. A rounded corner needs alpha to survive, so a JPEG is squared
    /// rather than matted onto an invented background color.
    static func fileData(
        from image: CGImage, format: ScreenshotFileFormat, roundedCorners: Bool
    ) -> Data? {
        encoded(
            image,
            roundedCorners: roundedCorners && format.preservesTransparency,
            type: format.contentType,
            quality: format == .jpeg ? jpegQuality : nil)
    }

    /// High enough that a screenshot's text and UI edges stay clean.
    static let jpegQuality: CGFloat = 0.9

    private static func encoded(
        _ image: CGImage, roundedCorners: Bool, type: UTType, quality: CGFloat? = nil
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
        let properties = quality.map {
            [kCGImageDestinationLossyCompressionQuality as String: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, output, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
