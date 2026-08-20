import CoreGraphics
import CoreText
import Foundation

/// One editor mark-up mark. Geometry lives in image pixel space with a top-left origin, so the
/// live canvas and the flattened export share every coordinate.
struct ScreenshotAnnotation: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case arrow(start: CGPoint, end: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case freehand([CGPoint])
        case text(origin: CGPoint, string: String, fontSize: CGFloat)
    }

    var shape: Shape
    var color: ScreenshotAnnotationColor
    /// Stroke width in image pixels, resolved from the view scale when the mark is created.
    var width: CGFloat
}

/// The editor's fixed mark-up palette. These are content colors baked into the exported pixels,
/// not `Theme` tokens — an annotation must look identical in both appearances.
enum ScreenshotAnnotationColor: CaseIterable, Equatable, Sendable {
    case red, orange, yellow, green, blue, purple, black, white

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch self {
        case .red: (1.00, 0.23, 0.19, 1)
        case .orange: (1.00, 0.58, 0.00, 1)
        case .yellow: (1.00, 0.84, 0.04, 1)
        case .green: (0.20, 0.78, 0.35, 1)
        case .blue: (0.13, 0.46, 1.00, 1)
        case .purple: (0.69, 0.32, 0.87, 1)
        case .black: (0.00, 0.00, 0.00, 1)
        case .white: (1.00, 1.00, 1.00, 1)
        }
    }
}

/// Pure geometry the renderer and the harness share.
enum ScreenshotAnnotationGeometry {
    /// The filled head scales with the stroke so a heavy arrow never looks pin-tipped.
    static func arrowHead(
        from start: CGPoint, to end: CGPoint, width: CGFloat
    ) -> (tip: CGPoint, left: CGPoint, right: CGPoint, shaftEnd: CGPoint) {
        let length = max(hypot(end.x - start.x, end.y - start.y), 0.001)
        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let headLength = min(max(width * 4.5, 12), length)
        let headHalfWidth = headLength * 0.45
        let base = CGPoint(
            x: end.x - direction.x * headLength, y: end.y - direction.y * headLength)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        return (
            tip: end,
            left: CGPoint(
                x: base.x + normal.x * headHalfWidth, y: base.y + normal.y * headHalfWidth),
            right: CGPoint(
                x: base.x - normal.x * headHalfWidth, y: base.y - normal.y * headHalfWidth),
            // The shaft stops inside the head so the stroke cap never pokes past the tip.
            shaftEnd: base)
    }

    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y))
    }
}

/// Draws annotations into any CGContext whose space is image pixels with a top-left origin —
/// the live canvas hands one over directly and `flatten` builds the flipped bitmap itself.
enum ScreenshotAnnotationRenderer {
    static func draw(_ annotations: [ScreenshotAnnotation], in context: CGContext) {
        for annotation in annotations {
            context.saveGState()
            let (r, g, b, a) = annotation.color.rgba
            let color = CGColor(srgbRed: r, green: g, blue: b, alpha: a)
            context.setStrokeColor(color)
            context.setFillColor(color)
            context.setLineWidth(annotation.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            switch annotation.shape {
            case .arrow(let start, let end):
                let head = ScreenshotAnnotationGeometry.arrowHead(
                    from: start, to: end, width: annotation.width)
                context.move(to: start)
                context.addLine(to: head.shaftEnd)
                context.strokePath()
                context.move(to: head.tip)
                context.addLine(to: head.left)
                context.addLine(to: head.right)
                context.closePath()
                context.fillPath()
            case .rectangle(let rect):
                context.stroke(rect.insetBy(dx: annotation.width / 2, dy: annotation.width / 2))
            case .ellipse(let rect):
                context.strokeEllipse(
                    in: rect.insetBy(dx: annotation.width / 2, dy: annotation.width / 2))
            case .freehand(let points):
                guard let first = points.first else { break }
                context.move(to: first)
                if points.count == 1 { context.addLine(to: first) }
                for point in points.dropFirst() { context.addLine(to: point) }
                context.strokePath()
            case .text(let origin, let string, let fontSize):
                drawText(
                    string, at: origin, fontSize: fontSize, color: color, in: context)
            }
            context.restoreGState()
        }
    }

    /// The exported image: the capture with every annotation baked in, at native pixel size.
    static func flatten(image: CGImage, annotations: [ScreenshotAnnotation]) -> CGImage? {
        guard !annotations.isEmpty else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setShouldAntialias(true)
        context.draw(image, in: bounds)
        // The bitmap is y-up; annotations speak top-left y-down, so flip once for all of them.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        draw(annotations, in: context)
        return context.makeImage()
    }

    private static func drawText(
        _ string: String, at origin: CGPoint, fontSize: CGFloat, color: CGColor,
        in context: CGContext
    ) {
        guard !string.isEmpty else { return }
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, nil, nil)
        context.saveGState()
        // A soft dark halo keeps every palette color readable over busy or light pixels.
        context.setShadow(
            offset: .zero, blur: fontSize / 8,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
        // The renderer's space is y-down; CoreText draws y-up, so flip locally around the baseline.
        context.translateBy(x: origin.x, y: origin.y + ascent)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

}
