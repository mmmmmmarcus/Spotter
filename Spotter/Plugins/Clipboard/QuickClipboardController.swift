import AppKit
import Combine

@MainActor
final class QuickClipboardController {
    private let store: ClipboardStore
    private let hotKeys: HotKeyManager
    private var items: [ClipboardItem] = []
    private var selection = 0
    private var panel: QuickClipboardPanel?
    private var menu: QuickClipboardMenuView?
    private var motion: QuickClipboardMotion?
    private var departing: [UUID: QuickClipboardMotion] = [:]
    private var preparation: Task<Void, Never>?
    private var observation: AnyCancellable?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activation: NotificationToken?
    private var paste: ((ClipboardItem) -> Void)?
    private var restoreFocus: (() -> Void)?
    private var openHistory: (() -> Void)?
    private var generation = UUID()
    private(set) var isVisible = false
    private static let keys: [UInt16] = [53, 123, 124, 36, 76]

    init(store: ClipboardStore, hotKeys: HotKeyManager) {
        self.store = store
        self.hotKeys = hotKeys
    }

    isolated deinit {
        preparation?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        for key in Self.keys { hotKeys.releaseTransientKey(id: "quick-clipboard.\(key)") }
        motion?.stop()
        for animation in departing.values { animation.stop() }
    }

    func show(anchor request: QuickClipboardAnchor.Request, application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication, paste: @escaping (ClipboardItem) -> Void, restoreFocus: @escaping () -> Void, openHistory: @escaping () -> Void) {
        dismiss()
        self.paste = paste
        self.restoreFocus = restoreFocus
        self.openHistory = openHistory
        items = QuickClipboardPresentation.recentItems(store.items)
        selection = 0
        isVisible = true
        generation = UUID()
        let token = generation
        installObservers(sourcePID: application?.processIdentifier)
        preparation = Task { [weak self] in
            let anchor = await Task.detached(priority: .userInitiated) { await request.resolve() }.value
            guard !Task.isCancelled, let self, isVisible, generation == token else { return }
            let point = CGPoint(x: anchor.midX, y: anchor.midY)
            guard let display = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
                dismiss()
                return
            }
            let screen = display.visibleFrame
            await QuickClipboardMenuView.prepareThumbnails(for: items)
            guard !Task.isCancelled, isVisible, generation == token else { return }
            present(anchor: anchor, screen: screen)
            preparation = nil
        }
    }

    private func present(anchor: CGRect, screen: CGRect) {
        let currentWidths = QuickClipboardMenuView.widths(for: items)
        let target = QuickClipboardPresentation.frame(anchor: anchor, screen: screen, count: items.count,
            contentWidth: QuickClipboardPresentation.totalWidth(currentWidths))
        let point = CGPoint(x: anchor.midX, y: anchor.midY)
        let margin = QuickClipboardPresentation.canvasMargin
        let canvas = CGRect(origin: target.origin, size: QuickClipboardPresentation.size(count: items.count))
        let windowFrame = canvas.insetBy(dx: -margin - 8, dy: -margin - 8)
            .union(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)).integral
        let panel = QuickClipboardPanel(contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let root = NSView(frame: CGRect(origin: .zero, size: windowFrame.size))
        root.wantsLayer = true
        let menu = QuickClipboardMenuView(items: items)
        menu.update(items, selection: selection)
        menu.frame.origin = CGPoint(x: target.minX - margin - windowFrame.minX, y: target.minY - margin - windowFrame.minY)
        root.addSubview(menu)
        panel.contentView = root
        menu.onSelect = { [weak self] index in self?.activate(index) }
        menu.onHighlight = { [weak self] index in
            guard let self, isVisible else { return }
            selection = index
            self.menu?.select(index)
        }
        self.panel = panel
        self.menu = menu
        root.layoutSubtreeIfNeeded()
        let motion = QuickClipboardMotion(panel: panel, menu: menu,
            anchor: CGPoint(x: point.x - windowFrame.minX, y: point.y - windowFrame.minY))
        self.motion = motion
        motion.open(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        for key in Self.keys {
            hotKeys.holdTransientKey(id: "quick-clipboard.\(key)", shortcut: KeyShortcut(carbonKeyCode: Int(key), carbonModifiers: 0)) { [weak self] in
                self?.handle(key)
            }
        }
    }

    func dismiss(restoringFocus: Bool = false, animated: Bool = true) {
        let restore = restoringFocus ? restoreFocus : nil
        isVisible = false
        generation = UUID()
        preparation?.cancel()
        preparation = nil
        observation = nil
        activation = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        for key in Self.keys { hotKeys.releaseTransientKey(id: "quick-clipboard.\(key)") }
        panel?.ignoresMouseEvents = true
        menu?.onSelect = nil
        menu?.onHighlight = nil
        if let motion {
            if animated {
                let id = UUID()
                departing[id] = motion
                motion.close(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self] in
                    self?.departing[id] = nil
                }
            } else {
                motion.stop()
            }
        }
        if !animated {
            for animation in departing.values { animation.stop() }
            departing.removeAll()
        }
        motion = nil
        panel = nil
        menu = nil
        items = []
        paste = nil
        restoreFocus = nil
        openHistory = nil
        restore?()
    }

    private func installObservers(sourcePID: pid_t?) {
        observation = store.$items.sink { [weak self] latest in
            guard let self, isVisible else { return }
            let recent = QuickClipboardPresentation.recentItems(latest)
            if recent.count == items.count {
                let selectedHistory = selection == items.count
                let selectedID = items.indices.contains(selection) ? items[selection].id : nil
                items = recent
                selection = selectedHistory ? recent.count : (selectedID.flatMap { id in recent.firstIndex { $0.id == id } } ?? 0)
                menu?.update(items, selection: selection)
            } else {
                let ids = Set(latest.map(\.id))
                if items.contains(where: { !ids.contains($0.id) }) { dismiss() }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel {
                    self.dismiss()
                } else if let menu = self.menu, !menu.containsGlass(menu.convert(event.locationInWindow, from: nil)) {
                    self.dismiss()
                }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    if pid != sourcePID { self?.dismiss() }
                }
            }, center: center)
    }

    private func move(_ offset: Int) {
        guard isVisible else { return }
        selection = min(max(0, selection + offset), items.count)
        menu?.select(selection)
    }

    private func handle(_ key: UInt16) {
        guard isVisible else { return }
        switch key {
        case 53: dismiss(restoringFocus: true)
        case 124: move(1)
        case 123: move(-1)
        case 36, 76: activate(selection)
        default: break
        }
    }

    private func activate(_ index: Int) {
        guard isVisible else { return }
        if index == items.count {
            let action = openHistory
            dismiss(restoringFocus: true)
            action?()
            return
        }
        guard items.indices.contains(index),
            let current = store.items.first(where: { $0.id == items[index].id }) else { return }
        let action = paste
        dismiss()
        action?(current)
    }
}
