import AppKit
import QuartzCore

@MainActor
final class QuickClipboardMotion: NSObject {
    private let panel: NSPanel
    private let menu: QuickClipboardMenuView
    let animationLayer = CALayer()
    private let restingFrame: CGRect
    private let restingBounds: CGRect
    private let center: CGPoint
    private let collapsed: CGPoint
    private let now: () -> CFTimeInterval
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var duration: Double = 0
    private var sourceScale: CGFloat = 1
    private var targetScale: CGFloat = 1
    private var sourcePosition = CGPoint.zero
    private var targetPosition = CGPoint.zero
    private var sourceOpacity: Float = 0
    private var targetOpacity: Float = 1
    private var opacityDuration: Double = 0.145
    private var usesSpring = false
    private var completion: (() -> Void)?
    private var isClosing = false
    private var completionTask: Task<Void, Never>?

    init(panel: NSPanel, menu: QuickClipboardMenuView, anchor: CGPoint, now: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.panel = panel
        self.menu = menu
        self.now = now
        restingFrame = menu.frame
        restingBounds = menu.bounds
        center = CGPoint(x: menu.frame.midX, y: menu.frame.midY)
        collapsed = QuickClipboardPresentation.collapsedCenter(center: center, anchor: anchor)
        super.init()
        animationLayer.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        animationLayer.position = center
        panel.contentView?.layer?.addSublayer(animationLayer)
    }

    func open(reduceMotion: Bool) {
        prepareOpening(reduceMotion: reduceMotion)
        panel.orderFrontRegardless()
        startDisplayLink()
    }

    func prepareOpening(reduceMotion: Bool) {
        sourceScale = reduceMotion ? 1 : QuickClipboardPresentation.initialScale
        targetScale = 1
        sourcePosition = reduceMotion ? center : collapsed
        targetPosition = center
        sourceOpacity = 0
        targetOpacity = 1
        opacityDuration = reduceMotion ? 0.12 : 0.145
        duration = reduceMotion ? opacityDuration : QuickClipboardPresentation.openingDuration
        usesSpring = !reduceMotion
        installAnimations(moving: !reduceMotion)
        render(scale: sourceScale, position: sourcePosition, opacity: 0)
    }

    func close(reduceMotion: Bool, completion: @escaping () -> Void) {
        guard !isClosing else { return }
        let current = currentPresentation()
        isClosing = true
        self.completion = completion
        sourceScale = current.scale
        targetScale = reduceMotion ? current.scale : QuickClipboardPresentation.initialScale
        sourcePosition = current.position
        targetPosition = reduceMotion ? current.position : collapsed
        sourceOpacity = current.opacity
        targetOpacity = 0
        duration = reduceMotion ? 0.12 : QuickClipboardPresentation.closingDuration
        opacityDuration = duration
        usesSpring = false
        installAnimations(moving: !reduceMotion)
        render(scale: sourceScale, position: sourcePosition, opacity: sourceOpacity)
        startDisplayLink()
    }

    func stop() {
        completionTask?.cancel()
        completionTask = nil
        displayLink?.invalidate()
        displayLink = nil
        completion = nil
        panel.close()
        animationLayer.removeAllAnimations()
        animationLayer.removeFromSuperlayer()
        menu.frame = restingFrame
        menu.bounds = restingBounds
    }

    private func installAnimations(moving: Bool) {
        startedAt = now()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        animationLayer.removeAllAnimations()
        animationLayer.setValue(targetScale, forKeyPath: "transform.scale")
        animationLayer.position = targetPosition
        animationLayer.opacity = targetOpacity
        if moving {
            animate("transform.scale", from: sourceScale, to: targetScale, duration: duration, spring: usesSpring)
            animate("position", from: sourcePosition, to: targetPosition, duration: duration, spring: usesSpring)
        }
        animate("opacity", from: sourceOpacity, to: targetOpacity, duration: opacityDuration, spring: false)
        CATransaction.commit()
        completionTask?.cancel()
        completionTask = Task { [weak self, duration] in
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            self?.finish()
        }
    }

    private func animate(_ key: String, from: Any, to: Any, duration: Double, spring: Bool) {
        let animation: CABasicAnimation
        if spring {
            let value = CASpringAnimation(keyPath: key)
            value.mass = 1
            value.stiffness = 500
            value.damping = 2 * 0.8 * sqrt(500)
            value.initialVelocity = 0
            animation = value
        } else {
            animation = CABasicAnimation(keyPath: key)
            animation.timingFunction = CAMediaTimingFunction(name: isClosing ? .easeIn : .easeOut)
        }
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animationLayer.add(animation, forKey: key)
    }

    private func currentPresentation() -> (scale: CGFloat, position: CGPoint, opacity: Float) {
        let elapsed = now() - startedAt
        let progress = usesSpring ? QuickClipboardPresentation.springProgress(elapsed: elapsed)
            : CGFloat(QuickClipboardPresentation.fadeProgress(elapsed: elapsed, duration: duration, easeIn: isClosing))
        let opacityProgress = QuickClipboardPresentation.fadeProgress(elapsed: elapsed, duration: opacityDuration, easeIn: isClosing)
        let shown = animationLayer.presentation()
        return (
            shown?.value(forKeyPath: "transform.scale") as? CGFloat ?? sourceScale + (targetScale - sourceScale) * progress,
            shown?.position ?? CGPoint(x: sourcePosition.x + (targetPosition.x - sourcePosition.x) * progress,
                y: sourcePosition.y + (targetPosition.y - sourcePosition.y) * progress),
            shown?.opacity ?? sourceOpacity + (targetOpacity - sourceOpacity) * opacityProgress)
    }

    private func render(scale: CGFloat, position: CGPoint, opacity: Float) {
        let size = CGSize(width: restingFrame.width * scale, height: restingFrame.height * scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit owns backing-layer geometry; frame and fixed bounds keep native glass in the same coordinate space.
        menu.frame = CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2, width: size.width, height: size.height)
        menu.bounds = restingBounds
        menu.layoutSubtreeIfNeeded()
        CATransaction.commit()
        panel.alphaValue = CGFloat(opacity)
    }

    private func startDisplayLink() {
        guard displayLink == nil, let view = panel.contentView else { return }
        let link = view.displayLink(target: self, selector: #selector(updatePresentation))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func updatePresentation() {
        if now() - startedAt >= duration {
            finish()
            return
        }
        let current = currentPresentation()
        render(scale: current.scale, position: current.position, opacity: current.opacity)
    }

    private func finish() {
        completionTask?.cancel()
        completionTask = nil
        render(scale: targetScale, position: targetPosition, opacity: targetOpacity)
        displayLink?.invalidate()
        displayLink = nil
        if isClosing {
            panel.close()
            let callback = completion
            completion = nil
            callback?()
        }
    }
}
