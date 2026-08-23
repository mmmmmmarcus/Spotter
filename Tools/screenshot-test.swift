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

private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
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
    let base = (y * image.width + x) * 4
    return (pixels[base], pixels[base + 1], pixels[base + 2], pixels[base + 3])
}

private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    pixel(image, x: x, y: y).a
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

        let head = ScreenshotAnnotationGeometry.arrowHead(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), width: 4)
        check(head.tip == CGPoint(x: 100, y: 0), "the arrow head tip is the drag end")
        check(
            abs(head.left.y + head.right.y) < 0.001 && head.left.x == head.right.x,
            "the arrow head is symmetric around the shaft")
        check(
            head.shaftEnd.x < 100 && head.shaftEnd.x > 0,
            "the shaft stops inside the head")
        let stubby = ScreenshotAnnotationGeometry.arrowHead(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 0), width: 4)
        check(stubby.shaftEnd.x >= 0, "a tiny arrow clamps its head to the drag length")

        let base = solidImage(width: 100, height: 100)
        check(
            ScreenshotAnnotationRenderer.flatten(image: base, annotations: []) === base,
            "flattening zero annotations returns the capture untouched")
        let marked = ScreenshotAnnotationRenderer.flatten(
            image: base,
            annotations: [
                ScreenshotAnnotation(
                    shape: .rectangle(CGRect(x: 30, y: 30, width: 40, height: 40)),
                    color: .blue,
                    width: 4)
            ])
        check(marked != nil, "flattening a rectangle produces an image")
        if let marked {
            let edge = pixel(marked, x: 32, y: 50)
            check(
                edge.b > 180 && edge.r < 120,
                "the rectangle edge pixel takes the annotation color")
            let center = pixel(marked, x: 50, y: 50)
            check(
                center.r > 180 && center.b < 120,
                "the rectangle interior keeps the capture pixels")
        }

        check(
            ScreenshotCaptureScale.retina.pixelScale(nativeScale: 2) == 2
                && ScreenshotCaptureScale.oneX.pixelScale(nativeScale: 2) == 1,
            "capture scale honors or ignores the display's native density")
        check(
            ScreenshotCaptureScale.retina.pixelScale(nativeScale: 0.5) == 1,
            "a nonsense native scale never shrinks a retina capture")
        let retinaPixels = ScreenshotCaptureScale.retina.pixelSize(
            forPointSize: CGSize(width: 300, height: 200), nativeScale: 2)
        check(
            retinaPixels.width == 600 && retinaPixels.height == 400,
            "a retina capture doubles its point size on a 2x display")
        let onePixels = ScreenshotCaptureScale.oneX.pixelSize(
            forPointSize: CGSize(width: 300, height: 200), nativeScale: 2)
        check(
            onePixels.width == 300 && onePixels.height == 200,
            "a 1x capture keeps one pixel per point")
        let tiny = ScreenshotCaptureScale.oneX.pixelSize(
            forPointSize: CGSize(width: 0.2, height: 0.2), nativeScale: 2)
        check(tiny.width == 1 && tiny.height == 1, "a sub-pixel region still captures one pixel")

        check(
            ScreenshotFileFormat.png.preservesTransparency
                && !ScreenshotFileFormat.jpeg.preservesTransparency,
            "only PNG can carry a rounded corner")
        check(
            ScreenshotFileFormat.jpeg.fileExtension == "jpg"
                && ScreenshotFileFormat.png.fileExtension == "png",
            "each format names its own extension")
        let corner = solidImage(width: 40, height: 40)
        let pngRounded = ScreenshotImageProcessor.fileData(
            from: corner, format: .png, roundedCorners: true).flatMap(decodedImage)
        check(
            pngRounded.map { alpha($0, x: 0, y: 0) == 0 } == true,
            "a rounded PNG keeps its corner transparent")
        let jpegRounded = ScreenshotImageProcessor.fileData(
            from: corner, format: .jpeg, roundedCorners: true).flatMap(decodedImage)
        check(
            jpegRounded.map { alpha($0, x: 0, y: 0) == 255 } == true,
            "a JPEG squares the corner instead of encoding a black wedge")
        check(
            (ScreenshotImageProcessor.fileData(from: corner, format: .jpeg, roundedCorners: false)?
                .count ?? 0) > 0,
            "JPEG encoding produces data")

        let box = CGSize(width: 124, height: 73)
        let wide = ScreenshotThumbnail.outerSize(
            forPixelSize: CGSize(width: 1600, height: 900), maximum: box, border: 4)
        check(
            wide.width == 124 && wide.height <= 73,
            "a wide capture fills the thumbnail box's width")
        let tall = ScreenshotThumbnail.outerSize(
            forPixelSize: CGSize(width: 400, height: 1200), maximum: box, border: 4)
        check(
            tall.height == 73 && tall.width < 124,
            "a tall capture fits the box's height instead of letterboxing")
        check(
            ScreenshotThumbnail.outerSize(
                forPixelSize: CGSize(width: 65, height: 65), maximum: box, border: 4)
                == CGSize(width: 73, height: 73),
            "a square capture stays square inside its frame")
        let sliver = ScreenshotThumbnail.outerSize(
            forPixelSize: CGSize(width: 2000, height: 1), maximum: box, border: 4)
        check(
            sliver.height >= 1 + 8 && sliver.width <= 124,
            "a one-pixel-tall capture still gets a visible thumbnail")
        check(
            ScreenshotThumbnail.outerSize(forPixelSize: .zero, maximum: box, border: 4) == box,
            "an empty capture falls back to the full box")

        func fragment(_ text: String, _ x: Double, _ y: Double, _ h: Double = 0.05)
            -> ScreenshotTextLayout.Fragment
        {
            ScreenshotTextLayout.Fragment(
                string: text, box: CGRect(x: x, y: y, width: 0.2, height: h))
        }
        // Vision hands back fragments in no useful order; these arrive deliberately scrambled.
        let page = [
            fragment("world", 0.35, 0.80), fragment("Hello", 0.10, 0.80),
            fragment("third", 0.10, 0.40), fragment("second", 0.10, 0.60),
        ]
        check(
            ScreenshotTextLayout.text(from: page) == "Hello world\nsecond\nthird",
            "fragments reassemble top-to-bottom then left-to-right")
        check(ScreenshotTextLayout.lines(from: page).count == 3, "same-row fragments share a line")
        check(
            ScreenshotTextLayout.text(from: []).isEmpty,
            "no fragments recognize to an empty string")
        check(
            ScreenshotTextLayout.text(from: [fragment("", 0.1, 0.5), fragment("kept", 0.1, 0.5)])
                == "kept",
            "empty fragments drop out rather than padding the line")
        // A tall heading must not swallow the smaller row beneath it.
        let heading = fragment("Heading", 0.10, 0.70, 0.12)
        let below = fragment("body", 0.10, 0.66, 0.03)
        check(
            ScreenshotTextLayout.lines(from: [heading, below]).count == 2,
            "a tall fragment does not absorb a shorter one below it")
        check(
            ScreenshotTextLayout.overlap(
                of: CGRect(x: 0, y: 0, width: 1, height: 0.1),
                and: CGRect(x: 0, y: 0.2, width: 1, height: 0.1)) == 0,
            "fragments that never overlap vertically score zero")
        check(
            ScreenshotTextLayout.overlap(
                of: CGRect(x: 0, y: 0, width: 1, height: 0.1),
                and: CGRect(x: 0, y: 0, width: 1, height: 0.1)) == 1,
            "identical spans score a full overlap")

        if failures > 0 { exit(1) }
        print("All screenshot tests passed.")
    }
}
