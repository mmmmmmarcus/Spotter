import AppKit
import Combine

@MainActor
final class QuickClipboardController {
    private let store: ClipboardStore
    private let hotKeys: HotKeyManager
    private var items: [ClipboardItem] = []
    private var selection = 0
    private var filter: QuickClipboardFilter = .all
    private var hasMore = false
    private var placement: (anchor: CGRect, screen: CGRect)?
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
    private static let keys = QuickClipboardPresentation.navigationKeys
    private static let imageKeys = QuickClipboardPresentation.imageNavigationKeys
    private static var allKeys: [UInt16] { keys + imageKeys }

    init(store: ClipboardStore, hotKeys: HotKeyManager) {
        self.store = store
        self.hotKeys = hotKeys
    }

    isolated deinit {
        preparation?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        for key in Self.allKeys { hotKeys.releaseTransientKey(id: "quick-clipboard.\(key)") }
        motion?.stop()
        for animation in departing.values { animation.stop() }
    }

    func show(anchor request: QuickClipboardAnchor.Request, application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication, paste: @escaping (ClipboardItem) -> Void, restoreFocus: @escaping () -> Void, openHistory: @escaping () -> Void) {
        dismiss()
        self.paste = paste
        self.restoreFocus = restoreFocus
        self.openHistory = openHistory
        filter = .all
        items = store.historyPage(kind: filter.kind, limit: QuickClipboardPresentation.pageSize)
        hasMore = items.count == QuickClipboardPresentation.pageSize
        selection = 0
        isVisible = true
        generation = UUID()
        let token = generation
        installObservers(sourcePID: application?.processIdentifier)
        preparation = Task { [weak self] in
            let anchor = await request.resolve()
            guard !Task.isCancelled, let self, isVisible, generation == token else { return }
            let point = CGPoint(x: anchor.midX, y: anchor.midY)
            guard let display = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
                dismiss()
                return
            }
            let screen = display.visibleFrame
            present(anchor: anchor, screen: screen)
            preparation = nil
        }
    }

    private func present(anchor: CGRect, screen: CGRect) {
        placement = (anchor, screen)
        let panel = QuickClipboardPanel(contentRect: .zero,
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
        let root = NSView()
        root.wantsLayer = true
        let menu = QuickClipboardMenuView(items: items)
        root.addSubview(menu)
        panel.contentView = root
        menu.onSelect = { [weak self] index in self?.activate(index) }
        menu.onHighlight = { [weak self] index in
            guard let self, isVisible else { return }
            selection = index
            self.menu?.select(index, reveal: false)
        }
        menu.onFilter = { [weak self] filter in self?.selectFilter(filter) }
        menu.onLoadMore = { [weak self] in self?.loadMore() }
        self.panel = panel
        self.menu = menu
        updatePresentation(opening: true)
        for key in Self.keys {
            hotKeys.holdTransientKey(id: "quick-clipboard.\(key)", shortcut: KeyShortcut(carbonKeyCode: Int(key), carbonModifiers: 0)) { [weak self] in
                self?.handle(key)
            }
        }
        updateImageKeyClaims()
    }

    private func updatePresentation(opening: Bool = false) {
        guard let panel, let menu, let placement else { return }
        motion?.stop(closingPanel: false)
        menu.update(items, selection: selection, filter: filter)
        let target = QuickClipboardPresentation.frame(anchor: placement.anchor, screen: placement.screen, items: items, filter: filter)
        let point = CGPoint(x: placement.anchor.midX, y: placement.anchor.midY)
        let margin = QuickClipboardPresentation.canvasMargin
        let windowFrame = target.insetBy(dx: -margin - 8, dy: -margin - 8)
            .union(CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)).integral
        panel.setFrame(windowFrame, display: false)
        menu.frame.origin = CGPoint(x: target.minX - margin - windowFrame.minX, y: target.minY - margin - windowFrame.minY)
        panel.contentView?.layoutSubtreeIfNeeded()
        let motion = QuickClipboardMotion(panel: panel, menu: menu,
            anchor: CGPoint(x: point.x - windowFrame.minX, y: point.y - windowFrame.minY))
        self.motion = motion
        if opening { motion.open(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        else { panel.alphaValue = 1 }
    }

    private func selectFilter(_ filter: QuickClipboardFilter) {
        guard isVisible, self.filter != filter else { return }
        self.filter = filter
        updateImageKeyClaims()
        items = store.historyPage(kind: filter.kind, limit: QuickClipboardPresentation.pageSize)
        hasMore = items.count == QuickClipboardPresentation.pageSize
        selection = 0
        updatePresentation()
        menu?.select(0)
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
        for key in Self.allKeys { hotKeys.releaseTransientKey(id: "quick-clipboard.\(key)") }
        panel?.ignoresMouseEvents = true
        menu?.onSelect = nil
        menu?.onHighlight = nil
        menu?.onFilter = nil
        menu?.onLoadMore = nil
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
        placement = nil
        items = []
        paste = nil
        restoreFocus = nil
        openHistory = nil
        restore?()
    }

    private func installObservers(sourcePID: pid_t?) {
        observation = store.$items.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, isVisible else { return }
            let count = max(QuickClipboardPresentation.pageSize, items.count)
            let recent = store.historyPage(kind: filter.kind, limit: count)
            hasMore = recent.count == count
            let oldSize = QuickClipboardPresentation.size(items: items, filter: filter)
            let selectedHistory = selection == items.count
            let selectedID = items.indices.contains(selection) ? items[selection].id : nil
            if let selectedID, !recent.contains(where: { $0.id == selectedID }) {
                dismiss()
                return
            }
            items = recent
            selection = selectedHistory ? recent.count : (selectedID.flatMap { id in recent.firstIndex { $0.id == id } } ?? 0)
            if QuickClipboardPresentation.size(items: items, filter: filter) != oldSize { updatePresentation() }
            else { menu?.update(items, selection: selection, filter: filter) }
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

    private func loadMore() {
        guard isVisible, hasMore, let last = items.last else { return }
        let page = store.historyPage(kind: filter.kind, before: last.id, limit: QuickClipboardPresentation.pageSize)
        hasMore = page.count == QuickClipboardPresentation.pageSize
        let selectedHistory = selection == items.count
        items.append(contentsOf: page)
        if selectedHistory { selection = items.count }
        menu?.update(items, selection: selection, filter: filter)
    }

    private func move(_ offset: Int) {
        guard isVisible else { return }
        if offset > 0 && selection >= items.count - 1 { loadMore() }
        selection = min(max(0, selection + offset), items.count)
        menu?.select(selection)
    }

    private func moveGrid(_ direction: QuickClipboardGridDirection) {
        guard isVisible, filter == .image else { return }
        if hasMore, items.indices.contains(selection) {
            let target = direction == .right ? selection + 1 : selection + QuickClipboardPresentation.gridColumns
            let canContinue = direction == .down
                || (direction == .right && selection % QuickClipboardPresentation.gridColumns < QuickClipboardPresentation.gridColumns - 1)
            if canContinue && target >= items.count { loadMore() }
        }
        selection = QuickClipboardPresentation.gridSelection(from: selection, moving: direction, itemCount: items.count)
        menu?.select(selection)
    }

    private func updateImageKeyClaims() {
        for key in Self.imageKeys {
            let id = "quick-clipboard.\(key)"
            if filter == .image {
                hotKeys.holdTransientKey(id: id, shortcut: KeyShortcut(carbonKeyCode: Int(key), carbonModifiers: 0)) { [weak self] in
                    self?.handle(key)
                }
            } else {
                hotKeys.releaseTransientKey(id: id)
            }
        }
    }

    private func handle(_ key: UInt16) {
        guard isVisible else { return }
        switch key {
        case 53: dismiss(restoringFocus: true)
        case 48: selectFilter(filter.moved(by: 1))
        case 123: moveGrid(.left)
        case 124: moveGrid(.right)
        case 125:
            if filter == .image { moveGrid(.down) } else { move(1) }
        case 126:
            if filter == .image { moveGrid(.up) } else { move(-1) }
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
            let current = store.historyItem(id: items[index].id) else { return }
        let action = paste
        dismiss()
        action?(current)
    }
}
