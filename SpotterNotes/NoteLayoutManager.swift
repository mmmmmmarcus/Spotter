import UIKit

/// Draws what a Note's Markdown implies behind its text — todo boxes, bullet discs, the code panel, the quote bar and the rule — so the source stays exactly the Markdown typed.
final class NoteLayoutManager: NSLayoutManager {
    enum Decoration {
        case codeBlock(NSRange)
        case quoteBar(NSRange)
        case rule(NSRange)

        var range: NSRange {
            switch self {
            case .codeBlock(let range), .quoteBar(let range), .rule(let range): range
            }
        }

        func moved(to range: NSRange) -> Decoration {
            switch self {
            case .codeBlock: .codeBlock(range)
            case .quoteBar: .quoteBar(range)
            case .rule: .rule(range)
            }
        }
    }

    /// One todo box, drawn over the kerned-out state character of a `- [ ] ` marker.
    struct Checkbox {
        let range: NSRange
        let isDone: Bool
    }

    var decorations: [Decoration] = []
    var checkboxes: [Checkbox] = []
    /// Cleared list dashes, each drawn as a disc in the cell the dash left behind.
    var bullets: [NSRange] = []
    /// Fills a completed todo: the Note's tint, or the app accent when it has none.
    var accent = UIColor.tintColor

    private static let checkboxMargin: CGFloat = 1.5
    private static let checkboxStroke: CGFloat = 1.5
    private static let minimumBulletDiameter: CGFloat = 5
    /// A disc filling the whole decoration square reads as a blob beside body text.
    private static let bulletFraction: CGFloat = 0.38

    /// The styling pass stands down during an input method's composition, so stored ranges are moved with each edit exactly as the storage moves its attributes.
    override func processEditing(
        for textStorage: NSTextStorage, edited editMask: NSTextStorage.EditActions,
        range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange: NSRange
    ) {
        super.processEditing(
            for: textStorage, edited: editMask, range: newCharRange, changeInLength: delta,
            invalidatedRange: invalidatedRange)
        guard editMask.contains(.editedCharacters), delta != 0 || newCharRange.length > 0 else { return }
        // `newCharRange` describes the text after the edit; the stored ranges predate it.
        let edited = NSRange(location: newCharRange.location, length: max(newCharRange.length - delta, 0))
        let length = textStorage.length
        func adjust(_ range: NSRange) -> NSRange? {
            NoteEngine.adjusting(range, forEdit: edited, changeInLength: delta, documentLength: length)
        }
        decorations = decorations.compactMap { decoration in
            adjust(decoration.range).map(decoration.moved(to:))
        }
        checkboxes = checkboxes.compactMap { checkbox in
            adjust(checkbox.range).map { Checkbox(range: $0, isDone: checkbox.isDone) }
        }
        bullets = bullets.compactMap(adjust)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first, let context = UIGraphicsGetCurrentContext() else {
            return
        }
        let visible = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawCheckboxes(in: visible, at: origin, container: container, context: context)
        drawBullets(in: visible, at: origin, container: container, context: context)

        let width = max(container.size.width - container.lineFragmentPadding * 2, 0)
        let left = origin.x + container.lineFragmentPadding
        for decoration in decorations where NSIntersectionRange(decoration.range, visible).length > 0 {
            guard let rect = lineRect(for: decoration.range) else { continue }
            let top = origin.y + rect.minY
            switch decoration {
            case .codeBlock:
                fill(
                    CGRect(x: left, y: top, width: width, height: rect.height),
                    radius: NotesTheme.Radius.card, color: NotesTheme.Colors.controlSurface, in: context)
            case .quoteBar:
                fill(
                    CGRect(x: left, y: top, width: 2, height: rect.height), radius: 1,
                    color: NotesTheme.Colors.border, in: context)
            case .rule:
                fill(
                    CGRect(x: left, y: (origin.y + rect.midY).rounded(), width: width, height: 1),
                    radius: 0, color: NotesTheme.Colors.separator, in: context)
            }
        }
    }

    /// The todo whose box, grown by `slop`, contains a point in text-container coordinates.
    func checkbox(at point: CGPoint, slop: CGFloat) -> Checkbox? {
        guard let container = textContainers.first else { return nil }
        return checkboxes.first { checkbox in
            decorationBox(for: checkbox.range, at: .zero, in: container)?
                .insetBy(dx: -slop, dy: -slop).contains(point) == true
        }
    }

    private func drawBullets(
        in visible: NSRange, at origin: CGPoint, container: NSTextContainer, context: CGContext
    ) {
        context.setFillColor(UIColor.label.cgColor)
        for bullet in bullets where NSIntersectionRange(bullet, visible).length > 0 {
            guard let box = decorationBox(for: bullet, at: origin, in: container) else { continue }
            let diameter = max(Self.minimumBulletDiameter, (box.width * Self.bulletFraction).rounded())
            context.fillEllipse(
                in: CGRect(
                    x: (box.midX - diameter / 2).rounded(), y: (box.midY - diameter / 2).rounded(),
                    width: diameter, height: diameter))
        }
    }

    private func drawCheckboxes(
        in visible: NSRange, at origin: CGPoint, container: NSTextContainer, context: CGContext
    ) {
        for checkbox in checkboxes where NSIntersectionRange(checkbox.range, visible).length > 0 {
            guard let box = decorationBox(for: checkbox.range, at: origin, in: container) else { continue }
            let side = box.width
            let stroke = Self.checkboxStroke
            guard checkbox.isDone else {
                context.addPath(
                    rounded(box.insetBy(dx: stroke / 2, dy: stroke / 2), radius: NotesTheme.Radius.checkbox))
                context.setStrokeColor(NotesTheme.Colors.border.cgColor)
                context.setLineWidth(stroke)
                context.strokePath()
                continue
            }
            fill(box, radius: NotesTheme.Radius.checkbox, color: accent, in: context)
            // The view is flipped, so the tick dips to `maxY` in the middle and rises to `minY` on the right.
            context.move(to: CGPoint(x: box.minX + side * 0.26, y: box.midY + side * 0.02))
            context.addLine(to: CGPoint(x: box.minX + side * 0.44, y: box.maxY - side * 0.26))
            context.addLine(to: CGPoint(x: box.maxX - side * 0.22, y: box.minY + side * 0.26))
            context.setLineWidth(max(stroke, side * 0.14))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(NotesTheme.Colors.checkmark.cgColor)
            context.strokePath()
        }
    }

    /// The square a marker's decoration is drawn in, so a bullet and a todo box on neighbouring lines share one size and place.
    private func decorationBox(
        for marker: NSRange, at origin: CGPoint, in container: NSTextContainer
    ) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: marker, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let slot = boundingRect(forGlyphRange: glyphs, in: container)
        let side = (min(slot.height, slot.width) - Self.checkboxMargin * 2).rounded()
        guard side > 4 else { return nil }
        return CGRect(
            x: (origin.x + slot.minX + Self.checkboxMargin).rounded(),
            y: (origin.y + slot.midY - side / 2).rounded(), width: side, height: side)
    }

    /// The union of the line fragments a character range occupies, in text-container coordinates.
    private func lineRect(for range: NSRange) -> CGRect? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        var union: CGRect?
        enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
            union = union.map { $0.union(fragment) } ?? fragment
        }
        return union
    }

    private func fill(_ rect: CGRect, radius: CGFloat, color: UIColor, in context: CGContext) {
        context.addPath(rounded(rect, radius: radius))
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
