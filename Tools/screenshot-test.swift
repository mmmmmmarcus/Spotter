import CoreGraphics
import Foundation
import ImageIO

@MainActor private var failures = 0

@MainActor private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✓ \(message)")
    } else {
        print("✗ \(message)")
        failures += 1
    }
}

private func solidImage(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func decodedImage(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return pixels[(y * image.width + x) * 4 + 3]
}

@main
private enum ScreenshotTest {
    @MainActor
    static func main() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        check(
            ScreenshotGeometry.selectionRect(
                from: CGPoint(x: 500, y: 400),
                to: CGPoint(x: 100, y: 200),
                within: bounds)
                == CGRect(x: 100, y: 200, width: 400, height: 200),
            "reverse drag normalizes the selection")
        check(
            ScreenshotGeometry.selectionRect(
                from: CGPoint(x: 100, y: 100),
                to: CGPoint(x: 1600, y: -20),
                within: bounds)
                == CGRect(x: 100, y: 0, width: 1340, height: 100),
            "selection clamps to its display")

        let capture = ScreenshotGeometry.captureRect(
            fromScreenLocal: CGRect(x: 120, y: 100, width: 300, height: 200),
            screenHeight: 900)
        check(
            capture == CGRect(x: 120, y: 600, width: 300, height: 200),
            "display-local selection converts to top-origin capture space")
        let secondaryCapture = ScreenshotGeometry.captureRect(
            fromScreenLocal: CGRect(x: 50, y: 1500, width: 100, height: 200),
            screenHeight: 2048)
        check(
            secondaryCapture == CGRect(x: 50, y: 348, width: 100, height: 200),
            "secondary-display capture is independent of its global origin")

        check(ScreenshotGeometry.isCapturable(CGRect(x: 0, y: 0, width: 1, height: 1)),
              "one-point selection is capturable")
        check(!ScreenshotGeometry.isCapturable(CGRect(x: 0, y: 0, width: 0, height: 20)),
              "zero-width click is rejected")

        check(ScreenshotGeometry.cornerRadiusPixels == 4, "corner radius is exactly four pixels")
        check(
            ScreenshotGeometry.roundedCornerRadius(forPixelSize: CGSize(width: 6, height: 20)) == 3,
            "small captures clamp the radius to half their shortest side")

        let candidates = [
            ScreenshotWindowCandidate(
                id: 1, ownerPID: 501, layer: 0, alpha: 1,
                bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            ScreenshotWindowCandidate(
                id: 2, ownerPID: 502, layer: 0, alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 1440, height: 900)),
        ]
        check(
            ScreenshotWindowPicker.target(
                at: CGPoint(x: 200, y: 200), in: candidates, excluding: 999)?.id == 1,
            "the front-most window under the pointer wins")
        check(
            ScreenshotWindowPicker.target(
                at: CGPoint(x: 800, y: 200), in: candidates, excluding: 999)?.id == 2,
            "the pointer outside the front window falls through to the one below")
        check(
            ScreenshotWindowPicker.target(
                at: CGPoint(x: 200, y: 200), in: candidates, excluding: 501)?.id == 2,
            "Spotter's own overlay panels are never a capture target")
        check(
            ScreenshotWindowPicker.target(
                at: CGPoint(x: 2000, y: 2000), in: candidates, excluding: 999) == nil,
            "the pointer over no window highlights nothing")

        let rejected = [
            ScreenshotWindowCandidate(
                id: 3, ownerPID: 503, layer: 25, alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 400, height: 300)),
            ScreenshotWindowCandidate(
                id: 4, ownerPID: 504, layer: 0, alpha: 0,
                bounds: CGRect(x: 0, y: 0, width: 400, height: 300)),
            ScreenshotWindowCandidate(
                id: 5, ownerPID: 505, layer: 0, alpha: 1,
                bounds: CGRect(x: 0, y: 0, width: 400, height: 12)),
        ]
        check(
            ScreenshotWindowPicker.target(
                at: CGPoint(x: 10, y: 10), in: rejected, excluding: 999) == nil,
            "menu-bar layers, invisible windows and slivers are skipped")

        let flipped = ScreenshotWindowPicker.appKitRect(
            fromDisplaySpace: CGRect(x: 120, y: 100, width: 300, height: 200),
            primaryScreenMaxY: 900)
        check(
            flipped == CGRect(x: 120, y: 600, width: 300, height: 200),
            "a top-origin window rectangle flips into AppKit's global space")
        check(
            ScreenshotWindowPicker.displaySpacePoint(
                fromAppKit: CGPoint(x: 120, y: 600), primaryScreenMaxY: 900)
                == CGPoint(x: 120, y: 300),
            "an AppKit pointer location flips into window-server space")

        let source = solidImage(width: 12, height: 12)
        let roundedData = ScreenshotImageProcessor.tiffData(
            from: source, roundedCorners: true)
        let rounded = roundedData.flatMap(decodedImage)
        check(rounded?.width == 12 && rounded?.height == 12,
              "rounded TIFF preserves pixel dimensions")
        check(rounded.map { alpha($0, x: 0, y: 0) == 0 } == true,
              "rounded TIFF makes the corner transparent")
        check(rounded.map { alpha($0, x: 6, y: 6) == 255 } == true,
              "rounded TIFF preserves interior pixels")

        let squareData = ScreenshotImageProcessor.tiffData(
            from: source, roundedCorners: false)
        let square = squareData.flatMap(decodedImage)
        check(square.map { alpha($0, x: 0, y: 0) == 255 } == true,
              "disabled rounding preserves square corners")

        if failures > 0 { exit(1) }
        print("All screenshot tests passed.")
    }
}
