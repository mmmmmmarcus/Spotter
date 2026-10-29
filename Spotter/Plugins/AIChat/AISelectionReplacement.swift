import AppKit
import ApplicationServices

@MainActor
final class AISelectionReplacement {
    private let pid: pid_t
    private let original: String
    private let element: AXUIElement?
    private let range: NSRange?
    private let marker: CFTypeRef?
    private weak var textView: NSTextView?

    private init(pid: pid_t, original: String, element: AXUIElement? = nil,
        range: NSRange? = nil, marker: CFTypeRef? = nil, textView: NSTextView? = nil) {
        self.pid = pid
        self.original = original
        self.element = element
        self.range = range
        self.marker = marker
        self.textView = textView
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
            return AISelectionReplacement(pid: pid, original: text, range: view.selectedRange(), textView: view)
        }
        guard AXIsProcessTrusted(), let element = focusedElement(pid: pid),
              SelectedTextReader.selectedText(from: element) == text,
              isEditable(element)
        else { throw AISpellingResponse.Failure.unsupportedControl }
        let range = selectedRange(element)
        let marker = attribute("AXSelectedTextMarkerRange", from: element)
        guard range != nil || marker != nil else { throw AISpellingResponse.Failure.unsupportedControl }
        return AISelectionReplacement(pid: pid, original: text, element: element, range: range, marker: marker)
    }

    func replace(with text: String) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw AISpellingResponse.Failure.selectionChanged
        }
        if let view = textView, let range {
            guard view.window?.firstResponder === view, view.window?.isKeyWindow == true,
                  Self.localSelectionMatches(view, range: range, text: original)
            else { throw AISpellingResponse.Failure.selectionChanged }
            if text != original { view.insertText(text, replacementRange: range) }
            return
        }
        guard AXIsProcessTrusted(), let element, let focused = Self.focusedElement(pid: pid),
              CFEqual(focused, element), Self.isEditable(element), SelectedTextReader.selectedText(from: element) == original,
              range.map({ Self.selectedRange(element) == $0 })
                ?? marker.map({ saved in Self.attribute("AXSelectedTextMarkerRange", from: element).map { CFEqual(saved, $0) } ?? false }) == true
        else { throw AISpellingResponse.Failure.selectionChanged }
        guard text != original else { return }
        // A native paste preserves the editor's undo transaction; never reactivate a stale target.
        Paster.copyString(text)
        Paster.postCommandV(toPid: pid)
    }

    static func localSelectionMatches(_ view: NSTextView, range: NSRange, text: String) -> Bool {
        let value = view.string as NSString
        return view.isEditable && view.selectedRange() == range && range.location != NSNotFound
            && range.location <= value.length && range.length <= value.length - range.location
            && value.substring(with: range) == text
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

    private static func isEditable(_ element: AXUIElement) -> Bool {
        isSettable(kAXSelectedTextAttribute, on: element) || isSettable(kAXValueAttribute, on: element)
            || (attribute("AXEditable", from: element) as? Bool == true)
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &range), range.location >= 0, range.length > 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
