import AppKit
import ApplicationServices

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
    private let makePasteFallback: (() -> AISelectionPasteFallback)?

    var usesInlineProgress: Bool { pasteFallback == nil }

    init(original: Snapshot, text: NSAttributedString, read: @escaping () -> Snapshot?,
        write: @escaping Writer, isFocused: @escaping () -> Bool,
        makePasteFallback: (() -> AISelectionPasteFallback)? = nil) {
        self.original = original
        self.originalText = text
        self.read = read
        self.write = write
        self.isFocused = isFocused
        self.makePasteFallback = makePasteFallback
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
        guard let element = focusedElement(pid: pid),
              isSettable(kAXSelectedTextAttribute, on: element),
              isSettable(kAXSelectedTextRangeAttribute, on: element),
              let snapshot = snapshot(element), substring(snapshot.value, range: snapshot.selection) == text
        else { return capturePasteFallback(text: text, pid: pid) }
        return AISelectionReplacement(original: snapshot, text: NSAttributedString(string: text), read: {
            guard AXIsProcessTrusted() else { return nil }
            return self.snapshot(element)
        }, write: { expected, range, replacement, selection, _ in
            guard self.snapshot(element) == expected, setRange(range, on: element),
                  SelectedTextReader.selectedText(from: element) == substring(expected.value, range: range)
            else { return false }
            guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString,
                replacement.string as CFString) == .success else {
                _ = setRange(expected.selection, on: element)
                return false
            }
            guard attribute(kAXValueAttribute, from: element) as? String
                == (expected.value as NSString).replacingCharacters(in: range, with: replacement.string)
            else { return false }
            return setRange(selection, on: element)
        }, isFocused: {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let focused = focusedElement(pid: pid) else { return false }
            return CFEqual(element, focused)
        }, makePasteFallback: { makeNativePasteFallback(text: text, pid: pid) })
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
            // Some editors advertise AX setters but ignore writes; only retry after proving no text or selection was lost.
            if isFocused(), read() == original, let makePasteFallback {
                let fallback = makePasteFallback()
                guard fallback.isCurrent else { throw AISpellingResponse.Failure.selectionChanged }
                pasteFallback = fallback
                return
            }
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

    private static func isSettable(_ name: String, on element: AXUIElement) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func setRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var raw = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &raw) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
}

@MainActor
final class AISelectionPasteFallback {
    private let original: String
    private let validate: () -> Bool
    private let paste: (String) -> Void
    private let cleanup: () -> Void
    private var finished = false

    init(original: String, isCurrent: @escaping () -> Bool, paste: @escaping (String) -> Void,
        cleanup: @escaping () -> Void = {}) {
        self.original = original
        self.validate = isCurrent
        self.paste = paste
        self.cleanup = cleanup
    }

    var isCurrent: Bool { !finished && validate() }

    func replace(with text: String, readSelection: () async -> String?) async throws {
        defer { cancel() }
        try Task.checkCancellation()
        guard isCurrent else { throw AISpellingResponse.Failure.selectionChanged }
        let selected = await readSelection()
        try Task.checkCancellation()
        guard isCurrent, selected == original else { throw AISpellingResponse.Failure.selectionChanged }
        if text != original { paste(text) }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        cleanup()
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
