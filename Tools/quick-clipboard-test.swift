import AppKit
import QuartzCore

@main
@MainActor
struct QuickClipboardTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ value: Bool, _ message: String) {
        if value { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async {
        geometry()
        await caretAnchors()
        await caretDeadline()
        webCaretBounds()
        emptyWebEditorAnchor()
        await imagePreviews()
        await nativeSurface()
        scrolling()
        imageGrid()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func scrolling() {
        let items = textItems(1000)
        let menu = QuickClipboardMenuView(items: items)
        let size = menu.frame.size
        expect(menu.rowButtons.count <= 6 && menu.rowButtons.first?.content.title == items[0].text,
            "long history starts at the newest row with bounded native views")
        menu.select(600)
        expect(menu.frame.size == size && menu.rowButtons.count <= 6
            && menu.rowButtons.contains { $0.isSelected && $0.content.title == items[600].text },
            "keyboard navigation reveals older rows without growing the window or creating all rows")
        let footer = menu.historyButton.frame
        menu.scrollView.contentView.scroll(to: .zero)
        menu.scrollView.reflectScrolledClipView(menu.scrollView.contentView)
        expect(menu.rowButtons.last?.content.title == items.last?.text && menu.historyButton.frame == footer,
            "native scrolling reaches the last entry while the footer remains fixed")
        var selected: Int?
        menu.onSelect = { selected = $0 }
        menu.rowButtons.last?.performClick(nil)
        expect(selected == 999, "virtual rows paste their actual history index")
        menu.update(textItems(12), selection: 0, filter: .files)
        expect(menu.rowButtons.first?.content.title == "Entry 0", "changing category resets scrolling to the newest entry")
        expect(QuickClipboardFilter.allCases == [.all, .text, .image, .files]
            && QuickClipboardFilter.all.moved(by: -1) == .files
            && QuickClipboardFilter.files.moved(by: 1) == .all
            && QuickClipboardFilter.text.moved(by: 1) == .image,
            "Tab cycles through All and the three broad categories")
    }

    static func imageGrid() {
        let image = ClipboardItem(imagePath: "/tmp/grid-preview.png", sourceBundleID: nil)
        let items = Array(repeating: image, count: 1000)
        let frames = QuickClipboardPresentation.rowFrames(items: items, filter: .image)
        expect(frames.allSatisfy { $0.width == $0.height } && frames.prefix(3).allSatisfy { $0.maxY == frames[0].maxY }
            && frames[3].maxY < frames[0].minY && frames[1].minX > frames[0].maxX,
            "image tiles are square in three nonoverlapping columns, ordered left to right then downward")
        let menu = QuickClipboardMenuView(items: [])
        menu.update(items, selection: 0, filter: .image)
        let size = menu.frame.size
        expect(menu.rowButtons.count == 6 && menu.rowButtons.first?.frame == frames[0],
            "the default count rounds up to two complete image rows")
        menu.select(601)
        expect(menu.frame.size == size && menu.rowButtons.count <= 12
            && menu.rowButtons.contains { $0.isSelected && $0.frame == frames[601] },
            "older grid selection scrolls into view with bounded views and a fixed viewport")
        var selected: Int?
        menu.onSelect = { selected = $0 }
        menu.rowButtons.first { $0.isSelected }?.performClick(nil)
        expect(selected == 601, "a reused grid tile activates the correct history entry")
        menu.update(Array(items.prefix(4)), selection: 0, filter: .image)
        expect(menu.rowButtons.count == 4 && menu.rowButtons.last?.frame.minX == 0,
            "a partial image row starts at the left without stretching tiles")
        menu.update(textItems(5), selection: 0, filter: .text)
        expect(menu.rowButtons.allSatisfy { $0.content.image == nil && !$0.content.title.isEmpty },
            "text-only entries drop their symbols after switching from the image grid")
        menu.update(textItems(5), selection: 0, filter: .all)
        expect(menu.rowButtons.allSatisfy { $0.content.image != nil && !$0.content.squareImage },
            "All restores type symbols and list geometry")
        expect(QuickClipboardPresentation.navigationKeys.contains(48)
            && QuickClipboardPresentation.imageNavigationKeys == [123, 124],
            "Tab stays global to the quick panel while left and right are reserved for the image grid")
        expect(QuickClipboardPresentation.gridSelection(from: 0, moving: .right, itemCount: 8) == 1
            && QuickClipboardPresentation.gridSelection(from: 1, moving: .right, itemCount: 8) == 2
            && QuickClipboardPresentation.gridSelection(from: 2, moving: .right, itemCount: 8) == 2
            && QuickClipboardPresentation.gridSelection(from: 1, moving: .left, itemCount: 8) == 0
            && QuickClipboardPresentation.gridSelection(from: 0, moving: .left, itemCount: 8) == 0,
            "left and right move within an image-grid row without wrapping")
        expect(QuickClipboardPresentation.gridSelection(from: 1, moving: .down, itemCount: 8) == 4
            && QuickClipboardPresentation.gridSelection(from: 4, moving: .up, itemCount: 8) == 1
            && QuickClipboardPresentation.gridSelection(from: 5, moving: .down, itemCount: 8) == 7,
            "up and down preserve the grid column and choose the nearest tile in a partial row")
        expect(QuickClipboardPresentation.gridSelection(from: 7, moving: .down, itemCount: 8) == 8
            && QuickClipboardPresentation.gridSelection(from: 8, moving: .up, itemCount: 8) == 7
            && QuickClipboardPresentation.gridSelection(from: 8, moving: .left, itemCount: 8) == 8,
            "down reaches full history after the final row and up returns to the final image")
    }

    static func caretAnchors() async {
        expect(QuickClipboardAnchor.isEditableCaret(role: "AXGroup", editable: true, range: CFRange(location: 2, length: 0)),
            "contenteditable fields need not use a standard text role")
        expect(!QuickClipboardAnchor.isEditableCaret(role: "AXStaticText", editable: nil, range: CFRange(location: 2, length: 0)),
            "read-only text cannot be mistaken for an active input")
        expect(!QuickClipboardAnchor.isEditableCaret(role: "AXTextArea", editable: false, range: CFRange(location: 2, length: 0))
            && !QuickClipboardAnchor.isEditableCaret(role: "AXTextArea", editable: true, range: CFRange(location: 2, length: 3)),
            "read-only editors and text selections are not insertion carets")
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mouse = CGPoint(x: 900, y: 300)
        let caret = CGRect(x: 300, y: 400, width: 0, height: 18)
        let request = QuickClipboardAnchor.Request(mouse: mouse, localCaret: caret, processID: nil,
            primaryTop: 900, screens: [screen])
        expect(await request.resolve() == caret, "an active insertion caret takes priority over the mouse")
        let fallback = QuickClipboardAnchor.Request(mouse: mouse, localCaret: nil, processID: nil,
            primaryTop: 900, screens: [screen])
        expect(await fallback.resolve() == CGRect(origin: mouse, size: .zero), "no caret falls back to the originally captured mouse position")
        let below = QuickClipboardPresentation.frame(anchor: caret, screen: screen, items: textItems(3))
        expect(below.minX == caret.minX && below.maxY == caret.minY - 12, "caret menu prefers below even when both sides have room")
        let low = CGRect(x: 300, y: 20, width: 1, height: 18)
        let above = QuickClipboardPresentation.frame(anchor: low, screen: screen, items: textItems(3))
        expect(above.minY == low.maxY + 12, "a caret near the bottom edge flips the menu above")
        for invalid in [CGRect.zero, CGRect(x: 0, y: 0, width: 400, height: 18), CGRect(x: 2000, y: 0, width: 1, height: 18)] {
            let rejected = QuickClipboardAnchor.Request(mouse: mouse, localCaret: invalid, processID: nil,
                primaryTop: 900, screens: [screen])
            expect(await rejected.resolve() == CGRect(origin: mouse, size: .zero), "empty, element-sized and offscreen bounds cannot become caret anchors")
        }
        let quartz = CGRect(x: -500, y: -200, width: 1, height: 18)
        let converted = QuickClipboardAnchor.appKitRect(quartz: quartz, primaryTop: 900)
        expect(converted == CGRect(x: -500, y: 1082, width: 1, height: 18), "AX coordinates use the primary display origin even on a display above and to the left")
        expect(QuickClipboardAnchor.visibleCaret(converted, screens: [CGRect(x: -1440, y: 900, width: 1440, height: 900)]) == converted,
            "a visible caret on another display remains valid")
    }

    static func caretDeadline() async {
        let request = QuickClipboardAnchor.Request(mouse: CGPoint(x: 100, y: 100), localCaret: nil, processID: 123,
            primaryTop: 900, screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)])
        let quartz = CGRect(x: 300, y: 400, width: 1, height: 18)
        let ready = await request.resolve { _ in quartz }
        expect(ready == QuickClipboardAnchor.appKitRect(quartz: quartz, primaryTop: 900),
            "a promptly available external caret wins over the mouse deadline")
        let start = ContinuousClock.now
        let slow = await request.resolve { _ in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { continuation.resume(returning: quartz) }
            }
        }
        expect(slow == CGRect(origin: request.mouse, size: .zero) && start.duration(to: .now) < .milliseconds(200),
            "a noncancellable AX read cannot delay presentation until it completes")
        let cancelled = Task { await request.resolve { _ in
            try? await Task.sleep(for: .seconds(1))
            return quartz
        } }
        cancelled.cancel()
        expect(await cancelled.value == CGRect(origin: request.mouse, size: .zero),
            "cancelling menu preparation terminates anchor resolution")
    }

    static func webCaretBounds() {
        var selection = CFRange(location: 5, length: 0)
        var expected = CGRect(x: 500, y: 250, width: 1, height: 20)
        var empty = CGRect.zero
        let caretValue = AXValueCreate(.cgRect, &expected)!
        let emptyValue = AXValueCreate(.cgRect, &empty)!
        let marker = "opaque-test-marker" as CFString
        var numericBounds: CFTypeRef? = caretValue
        var numericRange: CFTypeRef? = AXValueCreate(.cfRange, &selection)!
        var markerLength: NSNumber? = 0
        var role = "AXTextArea"
        var markerReads = 0
        func read() -> CGRect? {
            QuickClipboardAnchor.insertionAnchor(attribute: { name in
                switch name {
                case "AXRole": return role as CFString
                case "AXSelectedTextRange": return numericRange
                case "AXSelectedTextMarkerRange": return marker
                default: return nil
                }
            }, parameterized: { name, _ in
                switch name {
                case "AXBoundsForRange": return numericBounds
                case "AXLengthForTextMarkerRange": markerReads += 1; return markerLength
                case "AXBoundsForTextMarkerRange": return caretValue
                default: return nil
                }
            })
        }
        expect(read() == expected && markerReads == 0, "working numeric caret bounds need no marker lookup")
        numericBounds = emptyValue
        expect(read() == expected, "empty numeric geometry falls back to collapsed web marker bounds")
        numericRange = nil
        expect(read() == expected, "marker-only editable controls provide a caret without a numeric range")
        markerLength = 3
        expect(read() == nil, "nonempty web selections are never treated as insertion carets")
        markerLength = nil
        expect(read() == nil, "marker geometry is refused when selection length is unknown")
        markerLength = 0
        selection.length = 3
        numericRange = AXValueCreate(.cfRange, &selection)!
        expect(read() == nil, "a known nonempty numeric selection cannot be overridden by a marker")
        numericRange = nil
        role = "AXStaticText"
        expect(read() == nil, "read-only web text cannot supply an insertion caret")
    }

    static func emptyWebEditorAnchor() {
        var selection = CFRange(location: 0, length: 0)
        var box = CGRect(x: 300, y: 400, width: 500, height: 80)
        var count: NSNumber = 0
        let marker = "empty-editor-marker" as CFString
        func read() -> CGRect? {
            QuickClipboardAnchor.insertionAnchor(attribute: { name in
                switch name {
                case "AXRole": return "AXTextArea" as CFString
                case "AXSelectedTextRange": return AXValueCreate(.cfRange, &selection)
                case "AXSelectedTextMarkerRange": return marker
                case "AXNumberOfCharacters": return count
                default: return nil
                }
            }, parameterized: { name, _ in
                switch name {
                case "AXLengthForTextMarkerRange": return 0 as CFNumber
                case "AXBoundsForTextMarkerRange": return AXValueCreate(.cgRect, &box)
                default: return nil
                }
            })
        }
        let expected = CGRect(x: 300, y: 400, width: 0, height: 1)
        expect(read() == expected, "empty web editors anchor at their top edge instead of the mouse")
        count = 1
        expect(read() == expected, "a placeholder newline in an empty rich editor can use its box anchor")
        count = 2
        expect(read() == nil, "editors with multiple characters never substitute their entire box for a precise caret")
        count = 0
        selection.location = 1
        expect(read() == nil, "the empty-editor fallback requires insertion at the beginning")
        selection.location = 0
        selection.length = 1
        expect(read() == nil, "selected text cannot trigger the empty-editor fallback")
        selection.length = 0
        box.size.height = 0
        expect(read() == nil, "zero-size web bounds do not create a false input anchor")
    }

    static func textItems(_ count: Int) -> [ClipboardItem] {
        (0..<count).map { ClipboardItem(text: "Entry \($0)", sourceBundleID: nil) }
    }

    static func geometry() {
        let screen = CGRect(x: -1440, y: -400, width: 1440, height: 1000)
        let mouse = CGRect(x: -900, y: 100, width: 0, height: 0)
        let below = QuickClipboardPresentation.frame(anchor: mouse, screen: screen, items: textItems(5))
        expect(below.maxY == mouse.minY - 12 && below.minX == mouse.maxX + 12, "menu opens below and right of the mouse on a secondary display")
        let low = CGRect(x: -900, y: -380, width: 0, height: 0)
        let above = QuickClipboardPresentation.frame(anchor: low, screen: screen, items: textItems(5))
        expect(above.minY == low.maxY + 12, "menu flips above when below is full")
        expect(screen.insetBy(dx: 8, dy: 8).contains(above), "flipped menu respects screen safety")
        for count in 1...5 {
            let frame = QuickClipboardPresentation.frame(anchor: mouse, screen: screen, items: textItems(count))
            let rows = QuickClipboardPresentation.rowFrames(items: textItems(count)).map { $0.offsetBy(dx: frame.minX, dy: frame.minY + QuickClipboardPresentation.listFrame(items: textItems(count)).minY) }
            expect(rows.first!.maxY == mouse.minY - 18 && rows.dropFirst().allSatisfy { $0.maxY <= rows.first!.minY },
                "the first row stays nearest the anchor for \(count) clipboard entries")
        }
        let compact = QuickClipboardPresentation.frame(anchor: CGRect(x: -5, y: 0, width: 0, height: 0),
            screen: screen, items: textItems(5))
        expect(compact.width == 276 && compact.maxX == -17, "the complete menu flips left at the screen edge")
        let anchor = CGPoint(x: 120, y: 420)
        let center = CGPoint(x: 380, y: 720)
        let collapsed = QuickClipboardPresentation.collapsedCenter(center: center, anchor: anchor)
        let corner = CGPoint(x: 200, y: 640)
        let transformed = CGPoint(x: collapsed.x + 0.5 * (corner.x - center.x), y: collapsed.y + 0.5 * (corner.y - center.y))
        expect(abs(transformed.x - (anchor.x + 0.5 * (corner.x - anchor.x))) < 0.001,
            "collapsed x really scales around the anchor instead of menu center")
        expect(abs(transformed.y - (anchor.y + 0.5 * (corner.y - anchor.y))) < 0.001,
            "collapsed y really scales around the anchor instead of menu center")
        let rects = QuickClipboardPresentation.rowFrames(items: textItems(5))
        expect(rects.count == 5 && rects.allSatisfy { $0.size == CGSize(width: 264, height: 32) },
            "five text entries share one menu row width")
        expect(QuickClipboardPresentation.size(items: textItems(5)) == CGSize(width: 276, height: 212),
            "the menu contains five entries, history, outer insets and a history gap")
        expect(QuickClipboardPresentation.rowFrames(items: []).isEmpty
            && QuickClipboardPresentation.size(items: []) == CGSize(width: 276, height: 96),
            "empty results keep an explanation above the footer")
        expect(zip(rects, rects.dropFirst()).allSatisfy { $0.minY >= $1.maxY },
            "store order runs top to bottom without overlapping hit targets")
        expect(rects.first!.maxY == 160 && rects.last!.minY == 0,
            "menu rows keep outer insets and separate the footer")
        expect(QuickClipboardPresentation.rowFrames(items: textItems(50)).count == 50
            && QuickClipboardPresentation.size(items: textItems(50)) == QuickClipboardPresentation.size(items: textItems(5)),
            "the document keeps older rows while the viewport remains compact")
        expect(QuickClipboardPresentation.size(items: textItems(50), visibleCount: 12).height == 436,
            "twelve visible text rows determine the viewport height")
        expect(QuickClipboardPresentation.size(items: textItems(50), visibleCount: 1).height == 212
            && QuickClipboardPresentation.size(items: textItems(50), visibleCount: 99).height == 436,
            "visible count is clamped to five through twelve")
        let bounded = QuickClipboardPresentation.frame(anchor: low, screen: CGRect(x: 0, y: 0, width: 800, height: 300), items: textItems(50), visibleCount: 12)
        expect(bounded.height == 284, "small screens cap the viewport while the document remains scrollable")
        let configuredMenu = QuickClipboardMenuView(items: [])
        configuredMenu.update(textItems(50), selection: 0, visibleCount: 12)
        expect(configuredMenu.rowButtons.count == 12, "the native viewport initially exposes twelve text records")
        configuredMenu.select(40)
        expect(configuredMenu.rowButtons.contains { $0.isSelected }, "configured viewport still scrolls to older records")
        let image = ClipboardItem(imagePath: "/tmp/image.png", sourceBundleID: nil)
        let mixed = QuickClipboardPresentation.rowFrames(items: [image] + textItems(1))
        expect(mixed.map(\.height) == [64, 32] && mixed[0].minY == mixed[1].maxY,
            "larger image rows and compact text rows have distinct nonoverlapping targets")
        let images = Array(repeating: image, count: 5)
        expect(QuickClipboardPresentation.size(items: images).height == 372
            && screen.insetBy(dx: 8, dy: 8).contains(QuickClipboardPresentation.frame(anchor: low, screen: screen, items: images)),
            "five enlarged images remain on screen")
        let filters = QuickClipboardPresentation.filterFrames
        expect(filters.count == QuickClipboardFilter.allCases.count
            && (filters.first!.minX + filters.last!.maxX) / 2 == 138
            && filters.allSatisfy { QuickClipboardPresentation.footerFrame.contains($0) },
            "all shared filters are centered inside the footer")
        expect(zip(filters, filters.dropFirst()).allSatisfy { $1.minX - $0.maxX >= 12 },
            "category buttons have visible spacing without shrinking their hit targets")
        expect(filters.last!.maxX < QuickClipboardPresentation.historyFrame.minX
            && QuickClipboardPresentation.historyFrame.maxX == 270,
            "full history stays on the right without overlapping filters")
        let peak = (0...150).map { QuickClipboardPresentation.springProgress(elapsed: Double($0) / 1000) }.max()!
        expect(peak > 1 && peak < 1.016, "spring overshoot keeps final scale within about 1.2 percent")
        expect(abs(QuickClipboardPresentation.springProgress(elapsed: 0.149) - 1) < 0.001,
            "the faster spring settles before its final frame without a visible snap")
        expect(QuickClipboardPresentation.fadeProgress(elapsed: 0, duration: 0.145, easeIn: false) == 0,
            "opacity fallback begins transparent before presentation exists")
        expect(QuickClipboardPresentation.fadeProgress(elapsed: 0.145, duration: 0.145, easeIn: false) == 1,
            "opacity fallback ends fully visible")
        expect(QuickClipboardPresentation.fadeProgress(elapsed: 0.5, duration: 1, easeIn: true) < 0.5
            && QuickClipboardPresentation.fadeProgress(elapsed: 0.5, duration: 1, easeIn: false) > 0.5,
            "opacity fallbacks preserve ease-in and ease-out timing")
    }

    static func imagePreviews() async {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quick-clipboard-preview-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("private-filename.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        let item = ClipboardItem(imagePath: url.path, sourceBundleID: nil)
        await QuickClipboardMenuView.prepareThumbnails(for: [item])
        let other = ClipboardItem(text: "Other entry", sourceBundleID: nil)
        let menu = QuickClipboardMenuView(items: [item, other])
        let glass = menu.rowButtons[0]
        let button = glass.content
        expect(button.title.isEmpty && button.imagePosition == .imageOnly, "image rows show no filename or text label")
        expect(button.image?.size == CGSize(width: 96, height: 48) && button.image?.isTemplate == false,
            "image rows carry a real downsampled preview with its aspect ratio preserved")
        expect(glass.bezelColor == nil, "native buttons have no custom tint")
        let rendered = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rendered)
        button.draw(button.bounds)
        NSGraphicsContext.restoreGraphicsState()
        expect(rendered.colorAt(x: 16, y: 4)!.alphaComponent == 0 && rendered.colorAt(x: 16, y: 16)!.alphaComponent > 0.9,
            "image drawing preserves eight points of vertical padding")
        expect(rendered.colorAt(x: 0, y: 8)!.alphaComponent < 0.1 && rendered.colorAt(x: 16, y: 8)!.alphaComponent > 0.9,
            "the image itself is clipped to rounded corners")
        for (selection, expected) in [(1, 0.5), (0, 1.0)] {
            menu.select(selection)
            rendered.bitmapData!.initialize(repeating: 0, count: rendered.bytesPerRow * rendered.pixelsHigh)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rendered)
            button.draw(button.bounds)
            NSGraphicsContext.restoreGraphicsState()
            expect(abs(rendered.colorAt(x: 16, y: 16)!.alphaComponent - expected) < 0.02,
                "image dims when unselected and restores on selection")
        }
        let gridMenu = QuickClipboardMenuView(items: [])
        gridMenu.update([item], selection: 0, filter: .image)
        let gridContent = gridMenu.rowButtons[0].content
        let side = Int(gridContent.bounds.width)
        let tile = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: tile)
        gridContent.draw(gridContent.bounds)
        NSGraphicsContext.restoreGraphicsState()
        expect(gridContent.bounds.width == gridContent.bounds.height
            && tile.colorAt(x: side / 2, y: 1)!.alphaComponent > 0.9
            && tile.colorAt(x: side / 2, y: side - 2)!.alphaComponent > 0.9,
            "wide image previews fill the square tile without letterboxing")
        let cached = ImageThumbnail.cached(url, maxPixel: 512)
        expect(cached?.size == CGSize(width: 320, height: 160), "display sizing does not mutate the shared cached image")
        menu.update([ClipboardItem(text: "Text after image", sourceBundleID: nil), other], selection: 0)
        expect(button.imagePosition == .imageLeading && button.title.contains("Text after image"),
            "live replacement restores normal text presentation")
        menu.update([ClipboardItem(imagePath: directory.appendingPathComponent("missing.png").path, sourceBundleID: nil), other], selection: 0)
        expect(button.title.isEmpty && button.image != nil, "unreadable images keep an icon fallback without leaking a path")
    }

    static func groupShadow(_ menu: QuickClipboardMenuView) {
        let shadows = menu.layer!.sublayers!.filter { $0.shadowOpacity > 0 }
        expect(shadows.count == 1, "the menu uses one area shadow")
        guard let shadow = shadows.first, let mask = shadow.mask as? CAShapeLayer, let path = mask.path else {
            expect(false, "area shadow has a glass cutout mask")
            return
        }
        let rows = menu.glassView.contentView!
        let buttons = rows.subviews.compactMap { $0 as? QuickClipboardButton }
        expect(mask.fillRule == .evenOdd && shadow.zPosition > menu.glassView.layer!.zPosition,
            "shadow is above the glass with transparent cutouts")
        expect(buttons.allSatisfy { button in
            let rect = button.convert(button.bounds, to: menu)
            return !path.contains(CGPoint(x: rect.midX, y: rect.midY), using: .evenOdd)
        }, "every menu row is excluded from the area shadow")
        let region = menu.glassView.frame
        expect(shadow.shadowPath!.boundingBoxOfPath == region,
            "one shadow follows the whole menu outline")
        expect(path.contains(CGPoint(x: region.midX, y: region.minY - 6), using: .evenOdd),
            "soft drop shadow remains visible below the region")
        for scale in [1, 2] {
            let width = Int(menu.bounds.width) * scale
            let height = Int(menu.bounds.height) * scale
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            mask.render(in: context)
            let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
            let exteriorX = Int(region.midX * CGFloat(scale))
            let exteriorY = Int((region.minY - 6) * CGFloat(scale))
            expect(pixels[(exteriorY * width + exteriorX) * 4 + 3] > 250,
                "rendered \(scale)x mask retains the exterior shadow region")
            expect(buttons.allSatisfy { button in
                let rect = button.convert(button.bounds, to: menu)
                let x = Int(rect.midX * CGFloat(scale))
                let y = Int(rect.midY * CGFloat(scale))
                return pixels[(y * width + x) * 4 + 3] == 0
            }, "rendered \(scale)x cutout pixels leave glass interiors fully transparent")
        }
    }

    static func nativeSurface() async {
        _ = NSApplication.shared
        let panel = QuickClipboardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        expect(!panel.canBecomeKey && !panel.canBecomeMain, "picker cannot take keyboard focus")
        let items = ["Hi", "Hello", String(repeating: "Long text ", count: 40), "1234", "你好 👋"]
            .map { ClipboardItem(text: $0, sourceBundleID: nil) }
        let menu = QuickClipboardMenuView(items: items)
        expect(menu.alphaValue == 1 && menu.glassView.alphaValue == 1, "glass ancestors keep full alpha")
        let rows = menu.glassView.contentView!
        let glass = menu.rowButtons
        expect(menu.subviews.compactMap { $0 as? NSGlassEffectView }.count == 1
            && menu.glassView.style == .clear && menu.glassView.cornerRadius == 16
            && menu.glassView.tintColor == nil && menu.glassView.alphaValue == 1,
            "the complete list shares one untinted native Clear glass surface")
        expect(glass.count == 5 && menu.filterButtons.count == 4
            && (glass + menu.filterButtons + [menu.historyButton]).allSatisfy { $0.isDescendant(of: rows) && !$0.isBordered && $0.alphaValue == 1 },
            "all actions stay inside the one glass surface without row bezels")
        expect(glass.map(\.frame) == QuickClipboardPresentation.rowFrames(items: textItems(5)),
            "native buttons use top-to-bottom equal-width menu geometry")
        expect(glass.allSatisfy { !$0.isHidden }, "all five entries and history stay visible")
        groupShadow(menu)
        let selectedButton = glass[0].content
        let unselectedButton = glass[1].content
        expect(selectedButton.textColor.alphaComponent == 1 && selectedButton.symbolColor.alphaComponent == 1
            && unselectedButton.textColor.alphaComponent == 0.35 && unselectedButton.symbolColor.alphaComponent == 0.5,
            "selection changes both text and symbol emphasis without fading glass")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            selectedButton.appearance = NSAppearance(named: name)
            selectedButton.effectiveAppearance.performAsCurrentDrawingAppearance {
                let color = selectedButton.textColor.usingColorSpace(.deviceRGB)!
                expect(name == .aqua ? color.redComponent < 0.25 : color.redComponent > 0.75,
                    "text resolves to a contrasting semantic label in \(name)")
            }
        }
        let renderedButton = QuickClipboardContentView(frame: CGRect(x: 0, y: 0, width: 98, height: 32))
        renderedButton.title = "Readable"
        renderedButton.font = .systemFont(ofSize: 12)
        renderedButton.imagePosition = .imageLeading
        renderedButton.image = NSImage(systemSymbolName: "textformat.alt", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        renderedButton.isSelected = true
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            renderedButton.appearance = NSAppearance(named: name)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 98, pixelsHigh: 32,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            renderedButton.draw(renderedButton.bounds)
            NSGraphicsContext.restoreGraphicsState()
            for columns in [0..<16, 22..<98] {
                var samples: [CGFloat] = []
                for y in 0..<32 {
                    for x in columns {
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if color.alphaComponent > 0.8 { samples.append(color.redComponent) }
                    }
                }
                expect(!samples.isEmpty && samples.allSatisfy { name == .aqua ? $0 < 0.25 : $0 > 0.75 },
                    "rendered symbol and text pixels contrast correctly in \(name)")
            }
        }
        selectedButton.appearance = nil
        expect(glass[0].title.isEmpty && glass[0].image == nil, "native bezel does not duplicate the custom preview content")
        let originalFrames = glass.map(\.frame)
        var activated: Int?
        menu.onSelect = { activated = $0 }
        menu.select(4)
        expect(glass.map(\.frame) == originalFrames && glass[4].isSelected && !glass[0].isSelected,
            "keyboard selection never scrolls or moves the five entries")
        menu.select(5)
        let more = menu.historyButton
        expect(more.frame == QuickClipboardPresentation.historyFrame && more.toolTip == "Open Clipboard History"
            && more.content.title.isEmpty && more.content.image != nil,
            "the footer history icon has an accessible name and a right-aligned target")
        expect(more.isSelected, "keyboard selection reaches full history")
        let hit = menu.hitTest(more.convert(CGPoint(x: 16, y: 16), to: menu.superview))
        expect(hit === more, "the history row receives clicks")
        more.performClick(nil)
        expect(activated == items.count && !panel.isKeyWindow, "history activation uses its own index without taking focus")
        glass[3].performClick(nil)
        expect(activated == 3, "clipboard entries still activate individually")
        menu.select(0)
        let empty = QuickClipboardMenuView(items: [])
        var emptyActivation: Int?
        empty.onSelect = { emptyActivation = $0 }
        empty.historyButton.performClick(nil)
        expect(empty.rowButtons.isEmpty && empty.filterButtons.count == 4 && emptyActivation == 0 && empty.historyButton.isEnabled,
            "empty history keeps a working full-history button")
        var chosenFilter: QuickClipboardFilter?
        empty.onFilter = { chosenFilter = $0 }
        for (index, option) in QuickClipboardFilter.allCases.enumerated() {
            empty.filterButtons[index].performClick(nil)
            expect(chosenFilter == option, "footer dispatches the shared \(option.title) filter")
            empty.update([], selection: 0, filter: option)
            expect(empty.filterButtons.enumerated().allSatisfy { $0.element.isSelected == ($0.offset == index) },
                "filter selection remains separate from history keyboard selection")
        }
        expect(menu.filterButtons[0].isSelected && !panel.isKeyWindow,
            "a new menu defaults to All and filtering never requires a key panel")
        let margin = QuickClipboardPresentation.canvasMargin
        expect(!menu.containsGlass(CGPoint(x: 5, y: 5)), "shadow padding is outside menu hit areas")
        expect(menu.containsGlass(CGPoint(x: margin + 30, y: margin + 18)), "row interior remains clickable")
        expect(menu.containsGlass(CGPoint(x: margin + 138, y: margin + 42)),
            "the gap above history belongs to the continuous menu surface")
        expect(!menu.containsGlass(CGPoint(x: margin, y: margin)), "rounded menu corners exclude transparent padding")
        for (index, button) in glass.enumerated() {
            let hit = menu.hitTest(button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: menu.superview))
            expect(hit === button, "vertical row \(index) receives its own clicks")
        }
        var updated = items
        updated[0] = ClipboardItem(text: String(repeating: "New content ", count: 30), sourceBundleID: nil)
        menu.update(updated, selection: 0)
        expect(glass.map(\.frame) == originalFrames && glass[0].content.title.hasPrefix("New content"),
            "live content changes preserve every menu hit target")
        menu.update(items, selection: 0)
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
        panel.setContentSize(root.bounds.size)
        root.wantsLayer = true
        menu.setFrameOrigin(CGPoint(x: 37, y: 51))
        root.addSubview(menu)
        panel.contentView = root
        root.layoutSubtreeIfNeeded()
        let anchor = CGPoint(x: 17, y: 29)
        let restingFrame = menu.frame
        let restingBounds = menu.bounds
        let backingAnchor = menu.layer!.anchorPoint
        let originalGlassFrame = menu.glassView.convert(menu.glassView.bounds, to: root)
        var time = 1000.0
        let motion = QuickClipboardMotion(panel: panel, menu: menu, anchor: anchor, now: { time })
        motion.prepareOpening(reduceMotion: false)
        let spring = motion.animationLayer.animation(forKey: "transform.scale") as? CASpringAnimation
        let movement = motion.animationLayer.animation(forKey: "position") as? CASpringAnimation
        expect(spring?.mass == 1 && abs((spring?.stiffness ?? 0) - 4600.556) < 0.01 && abs((spring?.damping ?? 0) - 108.523) < 0.01,
            "opening retimes the spring while preserving its damping ratio")
        expect(spring?.duration == 0.15 && movement?.duration == spring?.duration,
            "position and scale have one shared opening duration")
        expect(panel.alphaValue == 0 && !panel.isVisible, "animations are installed before the window can flash visible")
        expect(menu.layer?.anchorPoint == backingAnchor, "animation never rewrites AppKit's backing-layer anchor")
        expect(menu.layer?.animation(forKey: "position") == nil && menu.layer?.animation(forKey: "transform.scale") == nil,
            "spring animation lives on an independent driver, not AppKit's geometry")
        root.layoutSubtreeIfNeeded()
        let expectedOrigin = CGPoint(x: anchor.x + 0.5 * (restingFrame.minX - anchor.x),
            y: anchor.y + 0.5 * (restingFrame.minY - anchor.y))
        expect(abs(menu.frame.minX - expectedOrigin.x) < 0.001 && abs(menu.frame.minY - expectedOrigin.y) < 0.001
            && abs(menu.frame.width - 0.5 * restingFrame.width) < 0.001,
            "native layout preserves the true anchor-grown first frame")
        expect(abs(menu.bounds.width - restingBounds.width) < 0.001
            && abs(menu.bounds.height - restingBounds.height) < 0.001
            && menu.bounds.origin == restingBounds.origin, "scaling keeps the menu's content coordinates fixed")
        let shownGlassFrame = menu.glassView.convert(menu.glassView.bounds, to: root)
        expect(abs(shownGlassFrame.minX - (anchor.x + 0.5 * (originalGlassFrame.minX - anchor.x))) < 0.001
            && abs(shownGlassFrame.minY - (anchor.y + 0.5 * (originalGlassFrame.minY - anchor.y))) < 0.001,
            "native glass and its clipping region share the same animated coordinates")
        time += QuickClipboardPresentation.openingDuration * 0.3
        motion.close(reduceMotion: false) {}
        let closingScale = motion.animationLayer.animation(forKey: "transform.scale") as? CABasicAnimation
        let closingPosition = motion.animationLayer.animation(forKey: "position") as? CABasicAnimation
        let fromScale = closingScale?.fromValue as? CGFloat ?? 0
        let fromPosition = closingPosition?.fromValue as? CGPoint ?? .zero
        expect(fromScale > 0.5 && fromScale < 1,
            "closing resumes a partially opened scale instead of assuming one")
        expect(abs(fromPosition.x - (anchor.x + fromScale * (restingFrame.midX - anchor.x))) < 0.001
            && abs(fromPosition.y - (anchor.y + fromScale * (restingFrame.midY - anchor.y))) < 0.001,
            "closing position and scale stay on the same anchor-grown trajectory")
        expect(abs(menu.frame.width - restingFrame.width * fromScale) < 0.001,
            "the native view starts closing from the sampled intermediate frame")
        expect(closingScale?.duration == 0.08 && closingPosition?.duration == 0.08
            && closingScale?.toValue as? CGFloat == 0.2, "closing keeps its 20 percent endpoint and shared 80ms ease-in")
        motion.stop()
        let reduced = QuickClipboardMotion(panel: panel, menu: menu, anchor: anchor)
        reduced.prepareOpening(reduceMotion: true)
        expect(reduced.animationLayer.animation(forKey: "position") == nil
            && reduced.animationLayer.animation(forKey: "transform.scale") == nil, "Reduce Motion installs no movement or scale animation")
        let fade = reduced.animationLayer.animation(forKey: "opacity") as? CABasicAnimation
        expect(fade?.duration == 0.12, "Reduce Motion only fades for 120ms")
        reduced.close(reduceMotion: true) {}
        expect(reduced.animationLayer.animation(forKey: "position") == nil
            && reduced.animationLayer.animation(forKey: "transform.scale") == nil, "Reduce Motion closing also has no movement or scale")
        reduced.stop()
        let immediate = QuickClipboardMotion(panel: panel, menu: menu, anchor: anchor)
        immediate.prepareOpening(reduceMotion: false)
        immediate.close(reduceMotion: false) {}
        let reversal = immediate.animationLayer.animation(forKey: "transform.scale") as? CABasicAnimation
        expect((reversal?.fromValue as? CGFloat ?? 1) >= 0.5 && (reversal?.fromValue as? CGFloat ?? 1) < 0.6,
            "closing before the first presentation frame never jumps to full size")
        immediate.stop(closingPanel: false)
        menu.update([ClipboardItem(imagePath: "/tmp/image.png", sourceBundleID: nil)], selection: 0, filter: .image)
        let reflowed = menu.frame
        let rebased = QuickClipboardMotion(panel: panel, menu: menu, anchor: anchor)
        rebased.close(reduceMotion: false) {}
        let reflowScale = rebased.animationLayer.animation(forKey: "transform.scale") as? CABasicAnimation
        let reflowPosition = rebased.animationLayer.animation(forKey: "position") as? CABasicAnimation
        expect(reflowScale?.fromValue as? CGFloat == 1
            && reflowPosition?.fromValue as? CGPoint == CGPoint(x: reflowed.midX, y: reflowed.midY),
            "closing after filter reflow begins at the new resting frame")
        rebased.stop()
    }
}
