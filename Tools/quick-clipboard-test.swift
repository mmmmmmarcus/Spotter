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
        webCaretBounds()
        await imagePreviews()
        await nativeSurface()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
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
        let above = QuickClipboardPresentation.frame(anchor: caret, screen: screen, count: 3, contentWidth: 250)
        expect(above.minX == caret.minX && above.minY == caret.maxY + 12, "caret menu opens directly above the insertion point")
        let high = CGRect(x: 300, y: 875, width: 1, height: 18)
        let below = QuickClipboardPresentation.frame(anchor: high, screen: screen, count: 3, contentWidth: 250)
        expect(below.maxY == high.minY - 12, "a caret near the top edge flips the menu below")
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
            QuickClipboardAnchor.caret(attribute: { name in
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

    static func geometry() {
        let screen = CGRect(x: -1440, y: -400, width: 1440, height: 1000)
        let mouse = CGRect(x: -900, y: -200, width: 0, height: 0)
        let above = QuickClipboardPresentation.frame(anchor: mouse, screen: screen, count: 5)
        expect(above.minY == mouse.maxY + 12 && above.minX == mouse.maxX + 12, "menu follows the mouse in global coordinates on a secondary display")
        let high = CGRect(x: -900, y: 550, width: 0, height: 0)
        let below = QuickClipboardPresentation.frame(anchor: high, screen: screen, count: 5)
        expect(below.maxY == high.minY - 12, "menu flips below when above is full")
        expect(screen.insetBy(dx: 8, dy: 8).contains(below), "flipped menu respects screen safety")
        let compact = QuickClipboardPresentation.frame(anchor: CGRect(x: -5, y: 0, width: 0, height: 0),
            screen: screen, count: 5, contentWidth: 210)
        expect(compact.width == 210 && compact.maxX == -17, "short horizontal pills anchor using real content width at screen edges")
        let anchor = CGPoint(x: 120, y: 420)
        let center = CGPoint(x: 380, y: 720)
        let collapsed = QuickClipboardPresentation.collapsedCenter(center: center, anchor: anchor)
        let corner = CGPoint(x: 200, y: 640)
        let transformed = CGPoint(x: collapsed.x + 0.2 * (corner.x - center.x), y: collapsed.y + 0.2 * (corner.y - center.y))
        expect(abs(transformed.x - (anchor.x + 0.2 * (corner.x - anchor.x))) < 0.001,
            "collapsed x really scales around the anchor instead of menu center")
        expect(abs(transformed.y - (anchor.y + 0.2 * (corner.y - anchor.y))) < 0.001,
            "collapsed y really scales around the anchor instead of menu center")
        let rects = QuickClipboardPresentation.rowFrames(count: 5)
        expect(rects.count == 6 && rects.last!.size == CGSize(width: 32, height: 32),
            "five recent entries are followed by one circular history button")
        expect(QuickClipboardPresentation.totalWidth([70, 90, 120, 32]) == 336,
            "fixed layout includes the history circle and all gaps")
        expect(QuickClipboardPresentation.size(count: 5).width == 672,
            "the complete strip reserves space for five capped pills and history")
        expect(QuickClipboardPresentation.rowFrames(count: 0).count == 1
            && QuickClipboardPresentation.size(count: 0).width == 32,
            "empty history still offers the full-history circle")
        expect(rects[1].minX - rects[0].maxX == 8, "pill spacing stays eight points")
        let peak = (0...455).map { QuickClipboardPresentation.springProgress(elapsed: Double($0) / 1000) }.max()!
        expect(peak > 1 && peak < 1.016, "spring overshoot keeps final scale within about 1.2 percent")
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
        let widths = QuickClipboardMenuView.widths(for: [item])
        expect(widths == [54, 32], "image pill hugs a 32-by-16 aspect-fit preview plus horizontal padding")
        let other = ClipboardItem(text: "Other entry", sourceBundleID: nil)
        let menu = QuickClipboardMenuView(items: [item, other])
        let surface = menu.glassContainer.contentView!.subviews[0].subviews[0] as! NSGlassEffectView
        let glass = surface.contentView as! QuickClipboardButton
        let button = glass.content
        expect(button.title.isEmpty && button.imagePosition == .imageOnly, "image rows show no filename or text label")
        expect(button.image?.size == CGSize(width: 32, height: 16) && button.image?.isTemplate == false,
            "image rows carry a real downsampled preview with its aspect ratio preserved")
        expect(glass.bezelColor == nil, "native buttons have no custom tint")
        let rendered = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
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
        let cached = ImageThumbnail.cached(url, maxPixel: 128)
        expect(cached?.size == CGSize(width: 128, height: 64), "display sizing does not mutate the shared cached image")
        menu.update([ClipboardItem(text: "Text after image", sourceBundleID: nil), other], selection: 0)
        expect(button.imagePosition == .imageLeading && button.title.contains("Text after image"),
            "live replacement restores normal text presentation")
        menu.update([ClipboardItem(imagePath: directory.appendingPathComponent("missing.png").path, sourceBundleID: nil), other], selection: 0)
        expect(button.title.isEmpty && button.image != nil, "unreadable images keep an icon fallback without leaking a path")
    }

    static func groupShadow(_ menu: QuickClipboardMenuView) {
        let shadows = menu.layer!.sublayers!.filter { $0.shadowOpacity > 0 }
        expect(shadows.count == 1, "all pills share one area shadow")
        guard let shadow = shadows.first, let mask = shadow.mask as? CAShapeLayer, let path = mask.path else {
            expect(false, "area shadow has a glass cutout mask")
            return
        }
        let rows = menu.glassContainer.contentView!.subviews[0]
        let pills = rows.subviews.compactMap { ($0 as? NSGlassEffectView)?.contentView as? QuickClipboardButton }.filter { !$0.isHidden }
        expect(mask.fillRule == .evenOdd && shadow.zPosition > menu.glassContainer.layer!.zPosition,
            "shadow is above the glass with transparent cutouts")
        expect(pills.allSatisfy { pill in
            let rect = pill.convert(pill.bounds, to: menu)
            return !path.contains(CGPoint(x: rect.midX, y: rect.midY), using: .evenOdd)
        }, "every visible pill is excluded from the area shadow, including the history circle")
        let region = menu.glassContainer.frame
        expect(shadow.shadowPath!.boundingBoxOfPath == region,
            "one shadow follows the width of the whole visible region")
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
            expect(pills.allSatisfy { pill in
                let rect = pill.convert(pill.bounds, to: menu)
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
        let widths = QuickClipboardMenuView.widths(for: items)
        let menu = QuickClipboardMenuView(items: items)
        expect(menu.alphaValue == 1 && menu.glassContainer.alphaValue == 1, "glass ancestors keep full alpha")
        let rows = menu.glassContainer.contentView!.subviews[0]
        let glass = rows.subviews.compactMap { ($0 as? NSGlassEffectView)?.contentView as? QuickClipboardButton }
        let surfaces = rows.subviews.compactMap { $0 as? NSGlassEffectView }
        expect(surfaces.count == 6 && surfaces.allSatisfy { $0.style == .clear && $0.cornerRadius == 16 && $0.tintColor == nil && $0.alphaValue == 1 },
            "every pill and history circle uses untinted native Clear glass")
        expect(glass.count == 6 && glass.allSatisfy { !$0.isBordered && $0.alphaValue == 1 },
            "borderless actions live inside the glass without a second glass bezel")
        expect(glass[0].frame.width < glass[1].frame.width && glass[1].frame.width < 120,
            "each short pill hugs its own native content width")
        expect(glass[2].frame.width == 120 && glass.allSatisfy { $0.frame.minY == 0 && $0.frame.height == 32 },
            "long content is capped at 120 points while pills share a horizontal baseline")
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
        let originalFrames = surfaces.map(\.frame)
        var activated: Int?
        menu.onSelect = { activated = $0 }
        menu.select(4)
        expect(surfaces.map(\.frame) == originalFrames && glass[4].content.isSelected,
            "keyboard selection never scrolls or moves the five entries")
        menu.select(5)
        let more = glass[5]
        expect(more.borderShape == .circle && more.frame.size == CGSize(width: 32, height: 32)
            && more.content.title.isEmpty && more.content.imagePosition == .imageOnly && more.content.image != nil,
            "the final entry is a circular symbol-only history control")
        expect(more.content.isSelected, "keyboard selection reaches full history")
        let hit = menu.hitTest(more.convert(CGPoint(x: 16, y: 16), to: menu.superview))
        expect(hit === more, "the history circle receives clicks")
        more.performClick(nil)
        expect(activated == items.count && !panel.isKeyWindow, "history activation uses its own index without taking focus")
        glass[3].performClick(nil)
        expect(activated == 3, "clipboard entries still activate individually")
        menu.select(0)
        let empty = QuickClipboardMenuView(items: [])
        let emptyRows = empty.glassContainer.contentView!.subviews[0]
        let emptyButtons = emptyRows.subviews.compactMap { ($0 as? NSGlassEffectView)?.contentView as? QuickClipboardButton }
        var emptyActivation: Int?
        empty.onSelect = { emptyActivation = $0 }
        emptyButtons[0].performClick(nil)
        expect(emptyButtons.count == 1 && emptyActivation == 0 && emptyButtons[0].isEnabled,
            "empty history keeps a working full-history button")
        let margin = QuickClipboardPresentation.canvasMargin
        expect(!menu.containsGlass(CGPoint(x: 5, y: 5)), "shadow padding is outside menu hit areas")
        expect(menu.containsGlass(CGPoint(x: margin + 30, y: margin + 18)), "pill interior remains clickable")
        expect(!menu.containsGlass(CGPoint(x: margin + glass[0].frame.maxX + 4, y: margin + glass[0].frame.midY)),
            "empty space beside a short pill is outside its hit area")
        var updated = items
        updated[0] = ClipboardItem(text: String(repeating: "New content ", count: 30), sourceBundleID: nil)
        menu.update(updated, selection: 0)
        expect(glass[0].frame.width == 120 && glass[0].content.frame.width == 98,
            "live history updates resize both glass and content")
        menu.update(items, selection: 0)
        expect(glass[0].frame.width == widths[0], "live content can shrink a pill back to its intrinsic width")
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
        let originalGlassFrame = menu.glassContainer.convert(menu.glassContainer.bounds, to: root)
        var time = 1000.0
        let motion = QuickClipboardMotion(panel: panel, menu: menu, anchor: anchor, now: { time })
        motion.prepareOpening(reduceMotion: false)
        let spring = motion.animationLayer.animation(forKey: "transform.scale") as? CASpringAnimation
        let movement = motion.animationLayer.animation(forKey: "position") as? CASpringAnimation
        expect(spring?.mass == 1 && spring?.stiffness == 500 && abs((spring?.damping ?? 0) - 35.777) < 0.01,
            "opening uses the specified lightly underdamped spring")
        expect(spring?.duration == 0.455 && movement?.duration == spring?.duration,
            "position and scale have one shared opening duration")
        expect(panel.alphaValue == 0 && !panel.isVisible, "animations are installed before the window can flash visible")
        expect(menu.layer?.anchorPoint == backingAnchor, "animation never rewrites AppKit's backing-layer anchor")
        expect(menu.layer?.animation(forKey: "position") == nil && menu.layer?.animation(forKey: "transform.scale") == nil,
            "spring animation lives on an independent driver, not AppKit's geometry")
        root.layoutSubtreeIfNeeded()
        let expectedOrigin = CGPoint(x: anchor.x + 0.2 * (restingFrame.minX - anchor.x),
            y: anchor.y + 0.2 * (restingFrame.minY - anchor.y))
        expect(abs(menu.frame.minX - expectedOrigin.x) < 0.001 && abs(menu.frame.minY - expectedOrigin.y) < 0.001
            && abs(menu.frame.width - 0.2 * restingFrame.width) < 0.001,
            "native layout preserves the true anchor-grown first frame")
        expect(abs(menu.bounds.width - restingBounds.width) < 0.001
            && abs(menu.bounds.height - restingBounds.height) < 0.001
            && menu.bounds.origin == restingBounds.origin, "scaling keeps the menu's content coordinates fixed")
        let shownGlassFrame = menu.glassContainer.convert(menu.glassContainer.bounds, to: root)
        expect(abs(shownGlassFrame.minX - (anchor.x + 0.2 * (originalGlassFrame.minX - anchor.x))) < 0.001
            && abs(shownGlassFrame.minY - (anchor.y + 0.2 * (originalGlassFrame.minY - anchor.y))) < 0.001,
            "native glass and its clipping region share the same animated coordinates")
        time += 0.075
        motion.close(reduceMotion: false) {}
        let closingScale = motion.animationLayer.animation(forKey: "transform.scale") as? CABasicAnimation
        let closingPosition = motion.animationLayer.animation(forKey: "position") as? CABasicAnimation
        let fromScale = closingScale?.fromValue as? CGFloat ?? 0
        let fromPosition = closingPosition?.fromValue as? CGPoint ?? .zero
        expect(fromScale > 0.2 && fromScale < 1,
            "closing resumes a partially opened scale instead of assuming one")
        expect(abs(fromPosition.x - (anchor.x + fromScale * (restingFrame.midX - anchor.x))) < 0.001
            && abs(fromPosition.y - (anchor.y + fromScale * (restingFrame.midY - anchor.y))) < 0.001,
            "closing position and scale stay on the same anchor-grown trajectory")
        expect(abs(menu.frame.width - restingFrame.width * fromScale) < 0.001,
            "the native view starts closing from the sampled intermediate frame")
        expect(closingScale?.duration == 0.2, "closing is a 200ms ease-in")
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
        expect((reversal?.fromValue as? CGFloat ?? 1) < 0.3,
            "closing before the first presentation frame never jumps to full size")
        immediate.stop()
    }
}
