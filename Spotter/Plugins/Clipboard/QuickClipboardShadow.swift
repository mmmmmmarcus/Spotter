import Foundation
import CoreGraphics
import Accelerate

enum QuickClipboardShadow {
    static func renderWindows(widths: [CGFloat], scale: CGFloat) -> [CGImage] {
        (0...max(0, widths.count - QuickClipboardPresentation.visibleLimit)).compactMap { first in
            render(widths: Array(widths.dropFirst(first).prefix(QuickClipboardPresentation.visibleLimit)), scale: scale)
        }
    }

    static func render(widths: [CGFloat], scale: CGFloat) -> CGImage? {
        let cornerRadius = QuickClipboardPresentation.cornerRadius
        let margin = QuickClipboardPresentation.shadowMargin
        let size = QuickClipboardPresentation.size(count: widths.count)
        let width = Int(ceil((size.width + margin * 2) * scale))
        let height = Int(ceil((size.height + margin * 2) * scale))
        let rects = QuickClipboardPresentation.rowFrames(widths: widths).map { $0.offsetBy(dx: margin, dy: margin) }
        var coverage = [UInt8](repeating: 0, count: width * height)
        let rendered = coverage.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            context.setFillColor(gray: 1, alpha: 1)
            for rect in rects {
                context.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -8), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            }
            context.fillPath()
            return true
        }
        guard rendered else { return nil }
        var mask = coverage.map { Float($0) / 255 }
        var blurred = [Float](repeating: 0, count: width * height)
        let sigma = 18 * Double(scale)
        let radius = Int(ceil(sigma * 3))
        var kernel = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
        let total = kernel.reduce(0, +)
        kernel = kernel.map { $0 / total }
        let error = mask.withUnsafeMutableBytes { source in
            blurred.withUnsafeMutableBytes { destination in
                var src = vImage_Buffer(data: source.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                var dst = vImage_Buffer(data: destination.baseAddress!, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                return kernel.withUnsafeBufferPointer { weights in
                    vImageSepConvolve_PlanarF(&src, &dst, nil, 0, 0, weights.baseAddress!, UInt32(kernel.count),
                        weights.baseAddress!, UInt32(kernel.count), 0, 0, vImage_Flags(kvImageBackgroundColorFill))
                }
            }
        }
        guard error == kvImageNoError else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = ((height - 1 - y) * width + x) * 4
                rgba[index + 3] = UInt8(max(0, min(255, Double(blurred[y * width + x]) * 0.22 * 255)))
            }
        }
        rgba.withUnsafeMutableBufferPointer { pixels in
            for rect in rects {
                let minX = max(0, Int(floor(rect.minX * scale)) - 1)
                let maxX = min(width - 1, Int(ceil(rect.maxX * scale)) + 1)
                let minY = max(0, Int(floor(rect.minY * scale)) - 1)
                let maxY = min(height - 1, Int(ceil(rect.maxY * scale)) + 1)
                let innerLeft = Int(ceil((rect.minX + cornerRadius) * scale - 0.5))
                let innerRight = Int(floor((rect.maxX - cornerRadius) * scale - 0.5))
                for y in minY...maxY {
                    let py = (CGFloat(y) + 0.5) / scale
                    let hasInterior = py >= rect.minY && py <= rect.maxY && innerRight >= innerLeft
                    if hasInterior {
                        let index = ((height - 1 - y) * width + innerLeft) * 4
                        pixels.baseAddress!.advanced(by: index).update(repeating: 0, count: (innerRight - innerLeft + 1) * 4)
                    }
                    let ranges = hasInterior ? [minX..<innerLeft, (innerRight + 1)..<(maxX + 1)] : [minX..<(maxX + 1)]
                    for range in ranges {
                        for x in range {
                            let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: py)
                            let distance = QuickClipboardPresentation.signedDistance(point, to: rect)
                            let coverage = max(0, min(1, distance * scale))
                            guard coverage < 1 else { continue }
                            let index = ((height - 1 - y) * width + x) * 4
                            // The one-pixel distance fringe attenuates every premultiplied channel together.
                            for channel in 0..<4 { pixels[index + channel] = UInt8(CGFloat(pixels[index + channel]) * coverage) }
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
