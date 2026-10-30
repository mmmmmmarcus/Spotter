import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class AISelectionReplacement {
    static let progressText = "{Fixing}"

    struct Snapshot: Equatable {
        let value: String
        let selection: NSRange
    }

    typealias Writer = (Snapshot, NSRange, NSAttributedString, NSRange, Bool) -> Bool
    private let original: Snapshot
    private let originalText: NSAttributedString
    private let read: () -> Snapshot?
    private let write: Writer
    private let isFocused: () -> Bool
    private var pending: Snapshot?
    private var pasteFallback: AISelectionPasteFallback?

    var usesInlineProgress: Bool { pasteFallback == nil || pasteFallback?.nativeProgress != nil }
    var restorationTask: Task<Bool, Never>? { pasteFallback?.nativeProgress?.settling }

    func finishRestoringWhenFocused() async {
        await pasteFallback?.nativeProgress?.finishRestoringWhenFocused()
    }

    func prepare() async throws {
        try showProgress()
        if let progress = pasteFallback?.nativeProgress { try await progress.begin() }
        try Task.checkCancellation()
    }

    init(original: Snapshot, text: NSAttributedString, read: @escaping () -> Snapshot?,
        write: @escaping Writer, isFocused: @escaping () -> Bool) {
        self.original = original
        self.originalText = text
        self.read = read
        self.write = write
        self.isFocused = isFocused
    }

    static func capture(text: String, pid: pid_t) throws -> AISelectionReplacement {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw AISpellingResponse.Failure.selectionChanged
        }
        if pid == ProcessInfo.processInfo.processIdentifier {
            guard let view = NSApp.keyWindow?.firstResponder as? NSTextView,
                  view.identifier == SelectedTextCapture.localSourceIdentifier,
                  localSelectionMatches(view, range: view.selectedRange(), text: text)
            else { throw AISpellingResponse.Failure.unsupportedControl }
            return captureLocal(view)
        }
        guard AXIsProcessTrusted() else { throw AISpellingResponse.Failure.unsupportedControl }
        return capturePasteFallback(text: text, pid: pid)
    }

    private static func capturePasteFallback(text: String, pid: pid_t) -> AISelectionReplacement {
        let fallback = makeNativePasteFallback(text: text, pid: pid)
        let target = AISelectionReplacement(original: Snapshot(value: text, selection: NSRange(location: 0, length: (text as NSString).length)),
            text: NSAttributedString(string: text), read: { nil }, write: { _, _, _, _, _ in false }, isFocused: { fallback.isCurrent })
        target.pasteFallback = fallback
        return target
    }

    private static func makeNativePasteFallback(text: String, pid: pid_t) -> AISelectionPasteFallback {
        let application = AXUIElementCreateApplication(pid)
        let element = focusedElement(pid: pid)
        let window = attribute(kAXFocusedWindowAttribute, from: application)
        let range = element.flatMap(selectedRange)
        let marker = element.flatMap { attribute("AXSelectedTextMarkerRange", from: $0) }
        if let element, let original = snapshot(element), substring(original.value, range: original.selection) == text {
            let progress = AISelectionNativeProgress(original: original, text: text,
                read: { self.snapshot(element) }, isFocused: {
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                        && sameElement(element, focusedElement(pid: pid))
                        && sameElement(window, attribute(kAXFocusedWindowAttribute, from: application))
                }, write: { expected, range, replacement, selection in
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
                    guard sameElement(element, focusedElement(pid: pid)),
                          sameElement(window, attribute(kAXFocusedWindowAttribute, from: application)),
                          self.snapshot(element) == expected else { return nil }
                    let value = (expected.value as NSString).replacingCharacters(in: range, with: replacement)
                    let needsSelection = expected.selection != range
                    if needsSelection {
                        guard range.length == AISelectionReplacement.progressText.count,
                              expected.selection == NSRange(location: NSMaxRange(range), length: 0) else { return nil }
                        for _ in 0..<range.length { postNativeKey(kVK_LeftArrow, flags: .maskShift, pid: pid) }
                    } else {
                        Paster.copyString(replacement)
                        postNativeKey(kVK_ANSI_V, flags: .maskCommand, pid: pid)
                    }
                    return Task { @MainActor in
                        if needsSelection {
                            guard await waitForSnapshot(element, value: expected.value, selection: range),
                                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                                  sameElement(element, focusedElement(pid: pid)),
                                  sameElement(window, attribute(kAXFocusedWindowAttribute, from: application)) else { return false }
                            Paster.copyString(replacement)
                            postNativeKey(kVK_ANSI_V, flags: .maskCommand, pid: pid)
                        }
                        let caret = NSRange(location: range.location + (replacement as NSString).length, length: 0)
                        guard await waitForSnapshot(element, value: value, selection: caret) else { return false }
                        if selection.length == 0 { return true }
                        guard selection.length == AISelectionReplacement.progressText.count,
                              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                              sameElement(element, focusedElement(pid: pid)),
                              sameElement(window, attribute(kAXFocusedWindowAttribute, from: application)) else { return false }
                        // Canvas editors can acknowledge AX ranges without moving their actual editing selection.
                        for _ in 0..<selection.length { postNativeKey(kVK_LeftArrow, flags: .maskShift, pid: pid) }
                        return await waitForSnapshot(element, value: value, selection: selection)
                    }
                })
            return AISelectionPasteFallback(original: text, isCurrent: { progress.isCurrent }, paste: { _ in }, nativeProgress: progress)
        }
        let activity = AISelectionActivityGuard()
        return AISelectionPasteFallback(original: text, isCurrent: {
            guard AXIsProcessTrusted(), !activity.changed,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  sameElement(element, focusedElement(pid: pid)),
                  sameElement(window, attribute(kAXFocusedWindowAttribute, from: application)) else { return false }
            if let element, let range { return selectedRange(element) == range }
            if let element, let marker { return sameElement(marker, attribute("AXSelectedTextMarkerRange", from: element)) }
            return true
        }, paste: { replacement in
            Paster.copyString(replacement)
            Paster.postCommandV(toPid: pid)
        }, cleanup: { activity.stop() })
    }

    private static func waitForSnapshot(_ element: AXUIElement, value: String, selection: NSRange) async -> Bool {
        for _ in 0..<30 {
            if snapshot(element) == Snapshot(value: value, selection: selection) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private static func postNativeKey(_ key: Int, flags: CGEventFlags, pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        for pressed in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: pressed)
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: HyperKeyTap.syntheticTag)
            event?.postToPid(pid)
        }
    }

    private static func sameElement(_ lhs: CFTypeRef?, _ rhs: CFTypeRef?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): CFEqual(lhs, rhs)
        default: false
        }
    }

    func complete(with text: String, readSelection: () async -> String?) async throws {
        if let pasteFallback {
            try await pasteFallback.replace(with: text, readSelection: readSelection)
        } else {
            try Task.checkCancellation()
            try replace(with: text)
        }
    }

    static func captureLocal(_ view: NSTextView, isFocused: (() -> Bool)? = nil) -> AISelectionReplacement {
        let range = view.selectedRange()
        let text = view.attributedString().attributedSubstring(from: range)
        return AISelectionReplacement(original: Snapshot(value: view.string, selection: range), text: text,
            read: { [weak view] in
                guard let view, view.isEditable, !view.hasMarkedText() else { return nil }
                return Snapshot(value: view.string, selection: view.selectedRange())
            }, write: { [weak view] expected, range, replacement, selection, recordUndo in
                guard let view, view.isEditable, !view.hasMarkedText(), view.string == expected.value,
                      view.selectedRange() == expected.selection else { return false }
                let undo = view.undoManager
                let disableUndo = !recordUndo && undo?.isUndoRegistrationEnabled == true
                if disableUndo { undo?.disableUndoRegistration() }
                defer { if disableUndo { undo?.enableUndoRegistration() } }
                guard view.shouldChangeText(in: range, replacementString: replacement.string),
                      let storage = view.textStorage else { return false }
                storage.replaceCharacters(in: range, with: replacement)
                view.didChangeText()
                guard view.string == (expected.value as NSString).replacingCharacters(in: range, with: replacement.string)
                else { return false }
                view.setSelectedRange(selection)
                return true
            }, isFocused: isFocused ?? { [weak view] in
                guard let view else { return false }
                return view.window?.isKeyWindow == true && view.window?.firstResponder === view
            })
    }

    func showProgress() throws {
        if let pasteFallback {
            guard pasteFallback.isCurrent else { throw AISpellingResponse.Failure.selectionChanged }
            return
        }
        guard pending == nil, isFocused(), read() == original else {
            throw AISpellingResponse.Failure.selectionChanged
        }
        let range = NSRange(location: original.selection.location, length: (Self.progressText as NSString).length)
        let value = (original.value as NSString).replacingCharacters(in: original.selection, with: Self.progressText)
        pending = Snapshot(value: value, selection: range)
        guard write(original, original.selection, NSAttributedString(string: Self.progressText), range, false),
              read() == pending else {
            restoreOriginal()
            throw AISpellingResponse.Failure.unsupportedControl
        }
    }

    func replace(with text: String) throws {
        guard let pending, let current = read(), current.value == pending.value, isFocused(),
              current.selection == pending.selection
                || current.selection == NSRange(location: NSMaxRange(pending.selection), length: 0)
        else { throw AISpellingResponse.Failure.selectionChanged }
        // Restore without recording the temporary text, so native Undo returns to the user's original.
        guard write(current, pending.selection, originalText, original.selection, false),
              let restored = read(), restored.value == original.value else {
            throw AISpellingResponse.Failure.selectionChanged
        }
        self.pending = nil
        guard text != originalText.string else { return }
        let attributes = originalText.length > 0 ? originalText.attributes(at: 0, effectiveRange: nil) : [:]
        let replacement = NSAttributedString(string: text, attributes: attributes)
        guard write(restored, original.selection, replacement,
            NSRange(location: original.selection.location + replacement.length, length: 0), true)
        else { throw AISpellingResponse.Failure.selectionChanged }
    }

    @discardableResult
    func restoreOriginal() -> Bool {
        if let pasteFallback { pasteFallback.cancel(); return true }
        guard let pending else { return true }
        defer { self.pending = nil }
        guard let current = read(), current.value == pending.value else { return false }
        let selection = Self.restoredSelection(current.selection, replacing: pending.selection, original: original.selection)
        return write(current, pending.selection, originalText, selection, false)
    }

    static func restoredSelection(_ selection: NSRange, replacing placeholder: NSRange, original: NSRange) -> NSRange {
        if selection.location >= NSMaxRange(placeholder) {
            return NSRange(location: selection.location + original.length - placeholder.length, length: selection.length)
        }
        if NSMaxRange(selection) <= placeholder.location { return selection }
        return original
    }

    static func localSelectionMatches(_ view: NSTextView, range: NSRange, text: String) -> Bool {
        view.isEditable && view.selectedRange() == range && substring(view.string, range: range) == text
    }

    private static func substring(_ value: String, range: NSRange) -> String? {
        let value = value as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= value.length, range.length <= value.length - range.location else { return nil }
        return value.substring(with: range)
    }

    private static func snapshot(_ element: AXUIElement) -> Snapshot? {
        guard let value = attribute(kAXValueAttribute, from: element) as? String,
              let range = selectedRange(element), substring(value, range: range) != nil else { return nil }
        return Snapshot(value: value, selection: range)
    }

    private static func focusedElement(pid: pid_t) -> AXUIElement? {
        guard let value = attribute(kAXFocusedUIElementAttribute, from: AXUIElementCreateApplication(pid)),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }


}

@MainActor
final class AISelectionPasteFallback {
    private let original: String
    private let validate: () -> Bool
    private let paste: (String) -> Void
    private let cleanup: () -> Void
    private var finished = false
    let nativeProgress: AISelectionNativeProgress?

    init(original: String, isCurrent: @escaping () -> Bool, paste: @escaping (String) -> Void,
        cleanup: @escaping () -> Void = {}, nativeProgress: AISelectionNativeProgress? = nil) {
        self.original = original
        self.validate = isCurrent
        self.paste = paste
        self.cleanup = cleanup
        self.nativeProgress = nativeProgress
    }

    var isCurrent: Bool { !finished && validate() }

    func replace(with text: String, readSelection: () async -> String?) async throws {
        defer { cancel() }
        try Task.checkCancellation()
        guard isCurrent else { throw AISpellingResponse.Failure.selectionChanged }
        if let nativeProgress {
            try await nativeProgress.finish(with: text)
            return
        }
        let selected = await readSelection()
        try Task.checkCancellation()
        guard isCurrent, selected == original else { throw AISpellingResponse.Failure.selectionChanged }
        if text != original { paste(text) }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        nativeProgress?.restore()
        cleanup()
    }
}

@MainActor
final class AISelectionNativeProgress {
    typealias Snapshot = AISelectionReplacement.Snapshot
    typealias Writer = (Snapshot, NSRange, String, NSRange) -> Task<Bool, Never>?
    private let original: Snapshot
    private let text: String
    private let read: () -> Snapshot?
    private let isFocused: () -> Bool
    private let write: Writer
    private var pending: Snapshot?
    private(set) var settling: Task<Bool, Never>?
    private var restorationInFlight = false

    init(original: Snapshot, text: String, read: @escaping () -> Snapshot?,
        isFocused: @escaping () -> Bool, write: @escaping Writer) {
        self.original = original
        self.text = text
        self.read = read
        self.isFocused = isFocused
        self.write = write
    }

    var isCurrent: Bool {
        guard isFocused(), let current = read() else { return false }
        guard let pending else { return current == original }
        return current.value == pending.value && (current.selection == pending.selection
            || current.selection == NSRange(location: NSMaxRange(pending.selection), length: 0))
    }

    func begin() async throws {
        guard isCurrent, pending == nil else { throw AISpellingResponse.Failure.selectionChanged }
        let placeholder = AISelectionReplacement.progressText
        let range = NSRange(location: original.selection.location, length: (placeholder as NSString).length)
        pending = Snapshot(value: (original.value as NSString).replacingCharacters(in: original.selection, with: placeholder), selection: range)
        settling = write(original, original.selection, placeholder, range)
        guard await settling?.value == true, isCurrent else {
            restore()
            throw AISpellingResponse.Failure.unsupportedControl
        }
    }

    func finish(with replacement: String) async throws {
        try Task.checkCancellation()
        guard isCurrent, let pending, let current = read() else { throw AISpellingResponse.Failure.selectionChanged }
        let end = NSRange(location: pending.selection.location + (replacement as NSString).length, length: 0)
        settling = write(current, pending.selection, replacement, end)
        guard await settling?.value == true else { throw AISpellingResponse.Failure.selectionChanged }
        self.pending = nil
    }

    func restore() {
        guard !restorationInFlight, let pending, let current = read(), current.value == pending.value,
              current.selection == pending.selection
                || current.selection == NSRange(location: NSMaxRange(pending.selection), length: 0) else { return }
        guard let operation = write(current, pending.selection, text, NSRange(location: NSMaxRange(original.selection), length: 0)) else { return }
        restorationInFlight = true
        settling = Task { @MainActor in
            let restored = await operation.value
            if restored { self.pending = nil }
            restorationInFlight = false
            return restored
        }
    }

    func finishRestoringWhenFocused() async {
        _ = await settling?.value
        guard pending != nil else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            continuation.yield(())
        }
        defer { center.removeObserver(token) }
        continuation.yield(())
        for await _ in stream {
            guard let pending else { return }
            guard read()?.value == pending.value else { self.pending = nil; return }
            if isCurrent {
                restore()
                if await settling?.value == true { return }
            }
        }
    }

}

@MainActor
private final class AISelectionActivityGuard {
    private(set) var changed = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.record(event)
            return event
        }
    }

    isolated deinit { stop() }

    private func record(_ event: NSEvent) {
        // Only ignore Spotter's own selection-copy events; never retain the user's keys or text.
        guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != HyperKeyTap.syntheticTag else { return }
        changed = true
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
