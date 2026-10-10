import AppKit
import SwiftUI

final class QuickAIChatPanel: NSPanel {
    let glassView: QuickAIChatGlassView
    private var appearanceObservation: NSKeyValueObservation?
    var onDismiss: (() -> Void)?
    var onHistoryKey: ((UInt16) -> Bool)?
    var composerOnlyBackdrop = false {
        didSet {
            (contentView as? QuickAIChatContainerView)?.composerOnlyBackdrop = composerOnlyBackdrop
        }
    }

    init<Content: View>(rootView: Content, size: CGSize, cornerRadius: CGFloat) {
        glassView = QuickAIChatGlassView(maximumCornerRadius: cornerRadius)
        super.init(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Quick AI Chat"
        appearance = Theme.QuickAI.appearance(for: NSApp.effectiveAppearance)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.managed, .participatesInCycle, .canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        let container = QuickAIChatContainerView(frame: CGRect(origin: .zero, size: size))
        glassView.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        glassView.autoresizingMask = [.width, .height]
        let host = NSHostingView(rootView: rootView)
        // Only the controller can resize the window during the two expansion stages.
        host.sizingOptions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(glassView)
        container.addSubview(host)
        container.glass = glassView
        contentView = container
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.appearance = Theme.QuickAI.appearance(for: NSApp.effectiveAppearance)
                self?.invalidateShadow()
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           (firstResponder as? NSTextView)?.hasMarkedText() != true,
           onHistoryKey?(event.keyCode) == true { return }
        if event.type == .keyDown, event.keyCode == 13,
           event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
            onDismiss?()
            return
        }
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            onDismiss?()
            return
        }
        super.sendEvent(event)
    }
}

private final class QuickAIChatContainerView: NSView {
    weak var glass: QuickAIChatGlassView?
    var composerOnlyBackdrop = false {
        didSet { needsLayout = true; layoutSubtreeIfNeeded() }
    }

    override func layout() {
        super.layout()
        glass?.frame = CGRect(x: 0, y: 0, width: bounds.width,
            height: composerOnlyBackdrop ? min(bounds.height, Theme.Size.quickAIComposerHeight) : bounds.height)
        window?.invalidateShadow()
    }
}

final class QuickAIChatGlassView: NSGlassEffectView {
    private let maximumCornerRadius: CGFloat

    init(maximumCornerRadius: CGFloat) {
        self.maximumCornerRadius = maximumCornerRadius
        super.init(frame: .zero)
        style = .regular
        wantsLayer = true
        // The native glass owns the sole clip, including the backing that otherwise leaks a rectangular fringe.
        layer?.masksToBounds = true
        updateCorners()
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateCorners()
    }

    override func layout() {
        super.layout()
        updateCorners()
    }

    private func updateCorners() {
        let radius = min(maximumCornerRadius, min(bounds.width, bounds.height) / 2)
        cornerRadius = radius
        layer?.cornerRadius = radius
        layer?.cornerCurve = bounds.height <= maximumCornerRadius * 2 ? .circular : .continuous
        window?.invalidateShadow()
    }
}

struct QuickAIChatCompactGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> QuickAIChatGlassView {
        QuickAIChatGlassView(maximumCornerRadius: Theme.Size.quickAIComposerHeight / 2)
    }
    func updateNSView(_ view: QuickAIChatGlassView, context: Context) {}
}

struct QuickAIChatDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> QuickAIChatDragView { QuickAIChatDragView() }
    func updateNSView(_ view: QuickAIChatDragView, context: Context) {}
}

final class QuickAIChatDragView: NSView {
    private let dragCursor = WindowDragCursor()
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        dragCursor.begin(in: self)
        window?.performDrag(with: event)
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) { dragCursor.end() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { dragCursor.end() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}
