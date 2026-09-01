import AppKit
import Carbon.HIToolbox

private func textReplacementEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<TextReplacementManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { manager.reenable() }
        return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
        MainActor.assumeIsolated { manager.resetPendingInput() }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let marker = event.getIntegerValueField(.eventSourceUserData)
    let flags = event.flags.rawValue
    var actualLength = 0
    var units = [UniChar](repeating: 0, count: 32)
    event.keyboardGetUnicodeString(
        maxStringLength: units.count, actualStringLength: &actualLength, unicodeString: &units)
    let text = String(utf16CodeUnits: units, count: actualLength)

    let match = MainActor.assumeIsolated {
        manager.handleKeyDown(keyCode: keyCode, flagsRaw: flags, marker: marker, text: text)
    }
    if let match {
        Task { @MainActor [weak manager] in manager?.apply(match) }
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class TextReplacementManager: ObservableObject {
    enum Status: Equatable {
        case off
        case idle
        case active
        case needsAccessibility
    }

    @Published private(set) var status: Status = .off

    private let store: TextReplacementStore
    private var engine: TextReplacementEngine
    private var isRunning = false
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var sessionTokens: [NotificationToken] = []

    init(store: TextReplacementStore) {
        self.store = store
        engine = TextReplacementEngine(prefix: store.prefix, snippets: store.snippets)
        store.onChange = { [weak self] prefix, snippets in
            self?.reload(prefix: prefix, snippets: snippets)
        }
    }

    isolated deinit {
        healthTimer?.invalidate()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSessionChanges()
        syncTapPresence()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sessionTokens.removeAll()
        stopHealthTimer()
        tearDownTap()
        status = .off
    }

    fileprivate func handleKeyDown(
        keyCode: Int, flagsRaw: UInt64, marker: Int64, text: String
    ) -> TextReplacementMatch? {
        guard marker != HyperKeyTap.syntheticTag else { return nil }
        let flags = CGEventFlags(rawValue: flagsRaw)
        let commandFlags = CGEventFlags([.maskCommand, .maskControl, .maskAlternate])
        if !flags.intersection(commandFlags).isEmpty {
            engine.reset()
            return nil
        }

        if keyCode == kVK_Delete {
            engine.deleteBackward()
            return nil
        }
        if keyCode == kVK_ForwardDelete || keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow
            || keyCode == kVK_UpArrow || keyCode == kVK_DownArrow || keyCode == kVK_Home
            || keyCode == kVK_End || keyCode == kVK_PageUp || keyCode == kVK_PageDown
        {
            engine.reset()
            return nil
        }
        guard !text.isEmpty else { return nil }
        return engine.consume(text)
    }

    fileprivate func resetPendingInput() {
        engine.reset()
    }

    fileprivate func reenable() {
        engine.reset()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    fileprivate func apply(_ match: TextReplacementMatch) {
        guard isRunning, status == .active, Permissions.isAccessibilityTrusted() else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<match.deletionCount {
            postKey(CGKeyCode(kVK_Delete), source: source)
        }
        for chunk in unicodeChunks(match.replacement) {
            postUnicode(chunk, source: source)
        }
    }

    private func reload(prefix: String, snippets: [Snippet]) {
        engine = TextReplacementEngine(prefix: prefix, snippets: snippets)
        guard isRunning else { return }
        syncTapPresence()
    }

    private func syncTapPresence() {
        guard isRunning else { return }
        if engine.isEmpty {
            stopHealthTimer()
            tearDownTap()
            status = .idle
        } else {
            startHealthTimer()
            installTapIfNeeded()
        }
    }

    private func installTapIfNeeded() {
        guard tapPort == nil, isRunning, !engine.isEmpty else { return }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: textReplacementEventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            status = .needsAccessibility
            return
        }
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        status = .active
    }

    private func tearDownTap() {
        engine.reset()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.healthCheck() }
        }
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func healthCheck() {
        guard isRunning, !engine.isEmpty else { return }
        if tapPort == nil {
            installTapIfNeeded()
        } else if !Permissions.isAccessibilityTrusted() {
            tearDownTap()
            status = .needsAccessibility
        } else if let tapPort, !CGEvent.tapIsEnabled(tap: tapPort) {
            CGEvent.tapEnable(tap: tapPort, enable: true)
        }
    }

    private func observeSessionChanges() {
        guard sessionTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sessionTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidResignActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.resetPendingInput()
                        if let tapPort = self?.tapPort {
                            CGEvent.tapEnable(tap: tapPort, enable: false)
                        }
                    }
                }, center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if let tapPort = self?.tapPort {
                            CGEvent.tapEnable(tap: tapPort, enable: true)
                        } else {
                            self?.installTapIfNeeded()
                        }
                    }
                }, center: center),
        ]
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        for event in [down, up] {
            event?.flags = []
            event?.setIntegerValueField(
                .eventSourceUserData, value: HyperKeyTap.syntheticTag)
            event?.post(tap: .cghidEventTap)
        }
    }

    private func postUnicode(_ text: String, source: CGEventSource?) {
        var units = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        for event in [down, up] {
            event?.flags = []
            event?.setIntegerValueField(
                .eventSourceUserData, value: HyperKeyTap.syntheticTag)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            event?.post(tap: .cghidEventTap)
        }
    }

    private func unicodeChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            let addition = String(character)
            if !current.isEmpty, current.utf16.count + addition.utf16.count > 20 {
                chunks.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
