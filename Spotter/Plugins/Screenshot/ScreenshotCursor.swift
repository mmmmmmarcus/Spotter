import AppKit
import SwiftUI

/// The two capture pointers and the frames that morph between them, rendered once from SF Symbols and shared by every selection panel.
@MainActor
enum ScreenshotCursor {
    static let pointSize: CGFloat = 24
    static let weight: NSFont.Weight = .medium
    static let outlineWidth: CGFloat = 1
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let shadowBlur: CGFloat = 2
    static let frameDuration =
        Theme.Animation.quick / Double(ScreenshotCursorTransition.frameCount)
    /// Offsets on a circle of `outlineWidth` dilate the glyph into an even outer border.
    private static let outlineSteps = 24

    static let region = cursor(from: regionArtwork)
    static let window = cursor(from: windowArtwork)
    static let screen = cursor(from: screenArtwork)

    private static let regionArtwork = artwork(symbolName: "dot.crosshair")
    private static let windowArtwork = artwork(symbolName: "camera.viewfinder")
    private static let screenArtwork = artwork(symbolName: "display")

    /// One entry per step of the Space cycle, composed on first use from artwork rasterized once —
    /// a frame is then two scaled draws. Keyed by the mode being entered, which is unambiguous
    /// because Space only ever advances the cycle.
    private static let transitions: [ScreenshotCaptureMode: [NSCursor]] = {
        guard let regionSource = regionArtwork, let windowSource = windowArtwork,
            let screenSource = screenArtwork
        else { return [:] }
        let region = rasterized(regionSource)
        let window = rasterized(windowSource)
        let screen = rasterized(screenSource)
        return [
            .window: frames(outgoing: region, incoming: window),
            .screen: frames(outgoing: window, incoming: screen),
            .region: frames(outgoing: screen, incoming: region),
        ]
    }()

    static func cursor(for mode: ScreenshotCaptureMode) -> NSCursor {
        switch mode {
        case .region: region
        case .window: window
        case .screen: screen
        }
    }

    /// The intermediate frames of a swap into `mode`; the animator lands on `cursor(for:)`, so a resting pointer is always the plain shared cursor.
    static func transitionFrames(into mode: ScreenshotCaptureMode) -> [NSCursor] {
        transitions[mode] ?? []
    }

    private static func frames(outgoing: NSImage, incoming: NSImage) -> [NSCursor] {
        // Every frame shares one canvas so the hotspot never shifts between the three symbols.
        let size = CGSize(
            width: max(outgoing.size.width, incoming.size.width),
            height: max(outgoing.size.height, incoming.size.height))
        // Step 0 is the pointer already on screen and the last step is the resting cursor the animator appends.
        return (1..<ScreenshotCursorTransition.frameCount).map { step in
            let schedule = ScreenshotCursorTransition.frame(at: step)
            let image = NSImage(size: size, flipped: false) { _ in
                draw(outgoing, in: size, scale: schedule.outgoingScale, alpha: schedule.outgoingAlpha)
                draw(incoming, in: size, scale: schedule.incomingScale, alpha: schedule.incomingAlpha)
                return true
            }
            return NSCursor(
                image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
        }
    }

    /// Both symbols stay centered on the hotspot, so the pointer never drifts while the swap plays.
    private static func draw(
        _ image: NSImage, in canvas: CGSize, scale: CGFloat, alpha: CGFloat
    ) {
        guard alpha > 0 else { return }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(
            in: CGRect(
                x: (canvas.width - size.width) / 2,
                y: (canvas.height - size.height) / 2,
                width: size.width,
                height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: alpha)
    }

    private static func cursor(from artwork: NSImage?) -> NSCursor {
        guard let artwork else { return .crosshair }
        return NSCursor(
            image: artwork,
            hotSpot: CGPoint(x: artwork.size.width / 2, y: artwork.size.height / 2))
    }

    private static func artwork(symbolName: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return shadowed(
            outlined(
                fill: tinted(symbol, configuration, Theme.Colors.screenshotCrosshairFill),
                outline: tinted(symbol, configuration, Theme.Colors.screenshotCrosshairOutline)))
    }

    private static func tinted(
        _ symbol: NSImage, _ configuration: NSImage.SymbolConfiguration, _ color: Color
    ) -> NSImage {
        let palette = NSImage.SymbolConfiguration(paletteColors: [NSColor(color)])
        return symbol.withSymbolConfiguration(configuration.applying(palette)) ?? symbol
    }

    private static func outlined(fill: NSImage, outline: NSImage) -> NSImage {
        let body = CGRect(
            origin: CGPoint(x: outlineWidth, y: outlineWidth), size: fill.size)
        let size = CGSize(
            width: (fill.size.width + outlineWidth * 2).rounded(.up),
            height: (fill.size.height + outlineWidth * 2).rounded(.up))
        return NSImage(size: size, flipped: false) { _ in
            for step in 0..<outlineSteps {
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(outlineSteps)
                outline.draw(
                    in: body.offsetBy(
                        dx: cos(angle) * outlineWidth, dy: sin(angle) * outlineWidth))
            }
            fill.draw(in: body)
            return true
        }
    }

    private static func shadowed(_ artwork: NSImage) -> NSImage {
        let padding = (shadowBlur + abs(shadowOffset.height)).rounded(.up)
        let size = CGSize(
            width: artwork.size.width + padding * 2, height: artwork.size.height + padding * 2)
        return NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            context.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: shadowOffset.width, height: shadowOffset.height)
            shadow.shadowBlurRadius = shadowBlur
            shadow.shadowColor = NSColor(Theme.Colors.screenshotCrosshairShadow)
            shadow.set()
            artwork.draw(
                in: CGRect(origin: CGPoint(x: padding, y: padding), size: artwork.size))
            context.restoreGraphicsState()
            return true
        }
    }

    /// A drawing-handler image ignores the destination rect, so the frames scale a bitmap copy instead. Frames only ever shrink it, so the deepest backing scale on the Mac stays sharp.
    private static func rasterized(_ image: NSImage) -> NSImage {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((image.size.width * scale).rounded(.up)),
            pixelsHigh: Int((image.size.height * scale).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return image }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let output = NSImage(size: image.size)
        output.addRepresentation(rep)
        return output
    }
}

/// Plays the Space swap by replacing the pointer image frame by frame — a hardware cursor has no animation of its own.
@MainActor
final class ScreenshotCursorAnimator {
    /// The pointer every panel should be showing right now: a transition frame while one plays, the resting cursor otherwise.
    private(set) var cursor: NSCursor = ScreenshotCursor.region
    /// Fired for every frame and for the resting cursor, so panels can push it to the window server.
    var onFrame: ((NSCursor) -> Void)?

    private var frames: [NSCursor] = []
    private var index = 0
    private var timer: Timer?

    func reset(to mode: ScreenshotCaptureMode) {
        stop()
        cursor = ScreenshotCursor.cursor(for: mode)
    }

    func transition(to mode: ScreenshotCaptureMode) {
        stop()
        let resting = ScreenshotCursor.cursor(for: mode)
        let playable = ScreenshotCursor.transitionFrames(into: mode)
        guard !playable.isEmpty else { show(resting); return }
        frames = playable + [resting]
        index = 0
        advance()
        timer = Timer.scheduledTimer(
            withTimeInterval: ScreenshotCursor.frameDuration, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        frames = []
        index = 0
    }

    private func advance() {
        guard index < frames.count else {
            stop()
            return
        }
        show(frames[index])
        index += 1
        if index == frames.count { stop() }
    }

    private func show(_ cursor: NSCursor) {
        self.cursor = cursor
        onFrame?(cursor)
    }
}
