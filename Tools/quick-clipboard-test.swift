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
        caretAnchors()
        let start = Date()
        let image = await Task.detached { QuickClipboardShadow.render(widths: [80, 240, 140], scale: 2) }.value
        print("2x shadow generation: \(Date().timeIntervalSince(start)) seconds")
        guard let image else { print("Shadow generation failed"); exit(1) }
        shadowPixels(image, scale: 2, widths: [80, 240, 140])
        let single = await Task.detached { QuickClipboardShadow.render(widths: [90], scale: 1) }.value
        if let single { shadowPixels(single, scale: 1, widths: [90]) }
        else { expect(false, "single-entry shadow generated") }
        await imagePreviews()
        await nativeSurface()
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func caretAnchors() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mouse = CGPoint(x: 900, y: 300)
        let caret = CGRect(x: 300, y: 400, width: 0, height: 18)
        let request = QuickClipboardAnchor.Request(mouse: mouse, localCaret: caret, processID: nil,
            primaryTop: 900, screens: [screen])
        expect(request.resolve() == caret, "an active insertion caret takes priority over the mouse")
        let fallback = QuickClipboardAnchor.Request(mouse: mouse, localCaret: nil, processID: nil,
            primaryTop: 900, screens: [screen])
        expect(fallback.resolve() == CGRect(origin: mouse, size: .zero), "no caret falls back to the originally captured mouse position")
        let above = QuickClipboardPresentation.frame(anchor: caret, screen: screen, count: 3, contentWidth: 250)
        expect(above.minX == caret.minX && above.minY == caret.maxY + 12, "caret menu opens directly above the insertion point")
        let high = CGRect(x: 300, y: 875, width: 1, height: 18)
        let below = QuickClipboardPresentation.frame(anchor: high, screen: screen, count: 3, contentWidth: 250)
        expect(below.maxY == high.minY - 12, "a caret near the top edge flips the menu below")
        for invalid in [CGRect.zero, CGRect(x: 0, y: 0, width: 400, height: 18), CGRect(x: 2000, y: 0, width: 1, height: 18)] {
            let rejected = QuickClipboardAnchor.Request(mouse: mouse, localCaret: invalid, processID: nil,
                primaryTop: 900, screens: [screen])
            expect(rejected.resolve() == CGRect(origin: mouse, size: .zero), "empty, element-sized and offscreen bounds cannot become caret anchors")
        }
        let quartz = CGRect(x: -500, y: -200, width: 1, height: 18)
        let converted = QuickClipboardAnchor.appKitRect(quartz: quartz, primaryTop: 900)
        expect(converted == CGRect(x: -500, y: 1082, width: 1, height: 18), "AX coordinates use the primary display origin even on a display above and to the left")
        expect(QuickClipboardAnchor.visibleCaret(converted, screens: [CGRect(x: -1440, y: 900, width: 1440, height: 900)]) == converted,
            "a visible caret on another display remains valid")
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
        expect(rects.count == 3, "only three clipboard entries are visible")
        expect(QuickClipboardPresentation.scrollOffset(first: 2, widths: [70, 90, 120, 60]) == 176,
            "horizontal scrolling follows cumulative content widths")
        expect(QuickClipboardPresentation.visibleWidth(first: 1, widths: [70, 90, 120, 60]) == 286,
            "viewport fits exactly the three current pills and their gaps")
        expect(QuickClipboardPresentation.size(count: 3) == QuickClipboardPresentation.size(count: 5),
            "browsing more entries does not resize the viewport")
        expect(QuickClipboardPresentation.firstVisibleIndex(selection: 2, current: 0, count: 5) == 0,
            "selecting the third entry does not scroll")
        expect(QuickClipboardPresentation.firstVisibleIndex(selection: 3, current: 0, count: 5) == 1,
            "the fourth entry pushes the first out")
        expect(QuickClipboardPresentation.firstVisibleIndex(selection: 4, current: 1, count: 5) == 2,
            "the fifth entry pushes the second out")
        expect(QuickClipboardPresentation.firstVisibleIndex(selection: 1, current: 2, count: 5) == 1,
            "moving above the viewport scrolls back")
        expect(QuickClipboardPresentation.firstVisibleIndex(selection: 0, current: 2, count: 0) == 0,
            "empty history resets the viewport")
        expect(QuickClipboardPresentation.scrollProgress(elapsed: 0) == 0
            && QuickClipboardPresentation.scrollProgress(elapsed: QuickClipboardPresentation.scrollDuration / 2) == 0.5
            && QuickClipboardPresentation.scrollProgress(elapsed: 1) == 1,
            "carrier scrolling has a bounded, symmetric easing curve")
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

    static func shadowPixels(_ image: CGImage, scale: CGFloat, widths: [CGFloat]) {
        let bytes = Array((image.dataProvider!.data! as Data))
        let margin = QuickClipboardPresentation.shadowMargin
        let rects = QuickClipboardPresentation.rowFrames(widths: widths).map { $0.offsetBy(dx: margin, dy: margin) }
        var interiorClear = true
        var premultiplied = true
        var hasShadow = false
        for y in 0..<image.height {
            for x in 0..<image.width {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(image.height - 1 - y) + 0.5) / scale)
                let index = y * image.bytesPerRow + x * 4
                let alpha = bytes[index + 3]
                let inside = rects.contains { QuickClipboardPresentation.signedDistance(point, to: $0) <= 0 }
                if inside && (0..<4).contains(where: { bytes[index + $0] != 0 }) { interiorClear = false }
                if (0..<3).contains(where: { bytes[index + $0] > alpha }) { premultiplied = false }
                if !inside && alpha > 0 { hasShadow = true }
            }
        }
        expect(interiorClear, "every \(scale)x glass interior is transparent in all RGBA channels")
        expect(premultiplied, "\(scale)x shadow remains premultiplied")
        expect(hasShadow, "\(scale)x shadow still exists outside the glass")
        func alpha(_ point: CGPoint) -> UInt8 {
            let x = Int(point.x * scale)
            let y = image.height - 1 - Int(point.y * scale)
            return bytes[y * image.bytesPerRow + x * 4 + 3]
        }
        let bottom = rects.last!
        expect(alpha(CGPoint(x: bottom.midX, y: bottom.minY - 1 / scale)) > 0,
            "\(scale)x shadow starts in the first pixel outside the contour, with no moat")
        expect(alpha(CGPoint(x: bottom.midX, y: bottom.minY - 4)) > alpha(CGPoint(x: bottom.midX, y: bottom.minY - 50)),
            "\(scale)x shadow decays away from the edge")
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
        expect(widths == [70], "image pill hugs a 48-by-24 aspect-fit preview plus horizontal padding")
        let menu = QuickClipboardMenuView(items: [item], shadowImages: [])
        let glass = menu.glassContainer.contentView!.subviews[0].subviews[0] as! NSGlassEffectView
        let button = glass.contentView!.subviews[0] as! NSButton
        expect(button.title.isEmpty && button.imagePosition == .imageOnly, "image rows show no filename or text label")
        expect(button.image?.size == CGSize(width: 48, height: 24) && button.image?.isTemplate == false,
            "image rows carry a real downsampled preview with its aspect ratio preserved")
        expect(button.contentTintColor == nil, "photo colors are not tinted by selection styling")
        let rendered = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 40,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rendered)
        button.draw(button.bounds)
        NSGraphicsContext.restoreGraphicsState()
        expect(rendered.colorAt(x: 24, y: 4)!.alphaComponent == 0 && rendered.colorAt(x: 24, y: 20)!.alphaComponent > 0.9,
            "image drawing preserves eight points of vertical padding")
        expect(rendered.colorAt(x: 0, y: 8)!.alphaComponent < 0.1 && rendered.colorAt(x: 24, y: 8)!.alphaComponent > 0.9,
            "the image itself is clipped to rounded corners")
        let cached = ImageThumbnail.cached(url, maxPixel: 128)
        expect(cached?.size == CGSize(width: 128, height: 64), "display sizing does not mutate the shared cached image")
        menu.update([ClipboardItem(text: "Text after image", sourceBundleID: nil)], selection: 0)
        expect(button.imagePosition == .imageLeading && button.title.contains("Text after image"),
            "live replacement restores normal text presentation")
        menu.update([ClipboardItem(imagePath: directory.appendingPathComponent("missing.png").path, sourceBundleID: nil)], selection: 0)
        expect(button.title.isEmpty && button.image != nil, "unreadable images keep an icon fallback without leaking a path")
    }

    static func nativeSurface() async {
        _ = NSApplication.shared
        let panel = QuickClipboardPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        expect(!panel.canBecomeKey && !panel.canBecomeMain, "picker cannot take keyboard focus")
        let items = ["Hi", "A slightly longer preview", String(repeating: "Long text ", count: 40), "1234", "你好 👋"]
            .map { ClipboardItem(text: $0, sourceBundleID: nil) }
        let widths = QuickClipboardMenuView.widths(for: items)
        let shadows = await Task.detached { QuickClipboardShadow.renderWindows(widths: widths, scale: 2) }.value
        expect(shadows.count == 3, "every visible range has its own matching shadow")
        var scrollTime = 100.0
        let menu = QuickClipboardMenuView(items: items, shadowImages: shadows, now: { scrollTime })
        expect(menu.alphaValue == 1 && menu.glassContainer.alphaValue == 1, "glass ancestors keep full alpha")
        let rows = menu.glassContainer.contentView!.subviews[0]
        let glass = rows.subviews.compactMap { $0 as? NSGlassEffectView }
        expect(glass.count == 5 && glass.allSatisfy { $0.style == .regular && $0.cornerRadius == 20 },
            "all five independent surfaces use native regular glass with 20-point corners")
        expect(glass[0].frame.width < glass[1].frame.width && glass[1].frame.width < 240,
            "each short pill hugs its own native content width")
        expect(glass[2].frame.width == 240 && glass.allSatisfy { $0.frame.minY == 0 && $0.frame.height == 40 },
            "long content is capped at 240 points while pills share a horizontal baseline")
        expect(glass.filter { !$0.isHidden }.count == 3, "offscreen pills start hidden")
        menu.select(3)
        expect(menu.firstVisibleIndex == 1 && glass[0].isHidden && !glass[3].isHidden && glass[4].isHidden,
            "fourth selection exposes the correct three entries")
        menu.layoutSubtreeIfNeeded()
        let visible = glass[3].convert(glass[3].bounds, to: menu.glassContainer.contentView!)
        expect(visible.maxX == rows.bounds.width && visible.height == QuickClipboardPresentation.rowHeight,
            "fourth entry occupies the rightmost visible slot")
        let button = glass[3].contentView!.subviews[0]
        let hit = menu.hitTest(button.convert(CGPoint(x: 30, y: 15), to: menu.superview))
        expect(hit === button, "scrolled entries remain hittable")
        menu.select(0)
        let originalPill = glass[0].frame
        let label = glass[0].contentView!.subviews[0]
        let originalLabel = label.convert(label.bounds, to: rows)
        menu.select(3, animated: true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            expect(menu.isScrolling && glass[0].frame == originalPill,
                "scroll starts at the displayed pill position instead of jumping its material")
            scrollTime += QuickClipboardPresentation.scrollDuration / 2
            menu.advanceScroll()
            let distance = (widths[0] + QuickClipboardPresentation.spacing) / 2
            expect(abs(glass[0].frame.minX - originalPill.minX + distance) < 0.001,
                "the actual glass carrier moves during the middle frame")
            expect(abs(label.convert(label.bounds, to: rows).minX - originalLabel.minX + distance) < 0.001,
                "text and the glass carrier move by the same distance")
            expect(glass[3].frame.minX < rows.bounds.maxX && glass[3].frame.maxX > rows.bounds.maxX && !glass[3].isHidden,
                "the incoming fourth pill enters through the right edge of the viewport")
            let interrupted = glass[0].frame
            menu.select(0, animated: true)
            expect(glass[0].frame == interrupted, "reversing scroll continues from the currently displayed carrier")
            scrollTime += QuickClipboardPresentation.scrollDuration + 0.01
            menu.advanceScroll()
            expect(!menu.isScrolling && glass[0].frame == originalPill,
                "reverse scrolling restores the first pill without text-only motion")
        }
        menu.select(4, animated: true)
        scrollTime += QuickClipboardPresentation.scrollDuration + 0.01
        menu.advanceScroll()
        expect(!menu.isScrolling && menu.firstVisibleIndex == 2 && glass.prefix(2).allSatisfy(\.isHidden)
            && glass.suffix(3).allSatisfy { !$0.isHidden },
            "rapid navigation settles on the newest requested range")
        menu.select(0)
        let margin = QuickClipboardPresentation.shadowMargin
        expect(!menu.containsGlass(CGPoint(x: 5, y: 5)), "shadow padding is outside menu hit areas")
        expect(menu.containsGlass(CGPoint(x: margin + 30, y: margin + 18)), "pill interior remains clickable")
        expect(!menu.containsGlass(CGPoint(x: margin + glass[0].frame.maxX + 4, y: margin + glass[0].frame.midY)),
            "empty space beside a short pill is outside its hit area")
        var updated = items
        updated[0] = ClipboardItem(text: String(repeating: "New content ", count: 30), sourceBundleID: nil)
        menu.update(updated, selection: 0)
        expect(glass[0].frame.width == 240 && glass[0].contentView!.subviews[0].frame.width == 218,
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
