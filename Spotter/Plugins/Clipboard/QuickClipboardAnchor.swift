import AppKit
import ApplicationServices

enum QuickClipboardAnchor {
    struct Request: Sendable {
        let mouse: CGPoint
        let localCaret: CGRect?
        let processID: pid_t?
        let primaryTop: CGFloat
        let screens: [CGRect]

        func resolve() async -> CGRect {
            if let localCaret, let valid = QuickClipboardAnchor.visibleCaret(localCaret, screens: screens) { return valid }
            if let processID, let quartz = await QuickClipboardAnchor.externalCaret(processID: processID) {
                let rect = QuickClipboardAnchor.appKitRect(quartz: quartz, primaryTop: primaryTop)
                if let valid = QuickClipboardAnchor.visibleCaret(rect, screens: screens) { return valid }
            }
            return CGRect(origin: mouse, size: .zero)
        }
    }

    @MainActor
    static func request(application: NSRunningApplication?, mouse: CGPoint) -> Request {
        var caret: CGRect?
        if application?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let window = NSApp.keyWindow, window.isVisible, window.isKeyWindow,
           let editor = window.firstResponder as? NSTextView, editor.isEditable,
           editor.selectedRange().location != NSNotFound, editor.selectedRange().length == 0 {
            caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        }
        let pid = application?.processIdentifier
        return Request(mouse: mouse, localCaret: caret,
            processID: pid == ProcessInfo.processInfo.processIdentifier ? nil : pid,
            primaryTop: NSScreen.screens.first?.frame.maxY ?? 0, screens: NSScreen.screens.map(\.frame))
    }

    static func appKitRect(quartz: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: primaryTop - quartz.maxY, width: quartz.width, height: quartz.height)
    }

    static func visibleCaret(_ rect: CGRect, screens: [CGRect]) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.width <= 8, rect.height >= 1, rect.height <= 200,
              screens.contains(where: { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) }) else { return nil }
        return rect
    }

    private static func externalCaret(processID: pid_t) async -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.08)
        if let rect = focusedCaret(application: application, processID: processID) { return rect }
        var restored: [String] = []
        var accessibilityEnabled = false
        // Chromium exposes its focused editor only after accessibility has been requested.
        for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            if (attribute(name, of: application) as? NSNumber)?.boolValue == true {
                accessibilityEnabled = true
            } else if AXUIElementSetAttributeValue(application, name as CFString, kCFBooleanTrue) == .success {
                accessibilityEnabled = true
                restored.append(name)
            }
        }
        defer {
            for name in restored { AXUIElementSetAttributeValue(application, name as CFString, kCFBooleanFalse) }
        }
        guard accessibilityEnabled else { return nil }
        // Electron builds its accessibility tree lazily; an immediate retry misses the editor.
        for _ in 0..<6 {
            do { try await Task.sleep(for: .milliseconds(60)) }
            catch { return nil }
            if let rect = focusedCaret(application: application, processID: processID) { return rect }
        }
        return nil
    }

    private static func focusedCaret(application: AXUIElement, processID: pid_t) -> CGRect? {
        for root in [application, AXUIElementCreateSystemWide()] {
            AXUIElementSetMessagingTimeout(root, 0.08)
            guard let raw = attribute(kAXFocusedUIElementAttribute, of: root),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let element = raw as! AXUIElement
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid == processID else { continue }
            AXUIElementSetMessagingTimeout(element, 0.08)
            if let rect = caret(of: element) { return rect }
        }
        return nil
    }

    static func isEditableCaret(role: String?, editable: Bool?, range: CFRange) -> Bool {
        let textRole = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains { $0 == role }
        return (textRole || editable == true) && editable != false && range.location >= 0 && range.length == 0
    }

    private static func caret(of element: AXUIElement) -> CGRect? {
        caret(attribute: { attribute($0, of: element) }, parameterized: { name, parameter in
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &result) == .success else { return nil }
            return result
        })
    }

    static func caret(attribute: (String) -> CFTypeRef?, parameterized: (String, CFTypeRef) -> CFTypeRef?) -> CGRect? {
        let role = attribute(kAXRoleAttribute) as? String
        let editable = (attribute("AXEditable") as? NSNumber)?.boolValue
        guard isEditableCaret(role: role, editable: editable, range: CFRange(location: 0, length: 0)) else { return nil }
        if let rawRange = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() {
            let value = rawRange as! AXValue
            var range = CFRange()
            guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
                  range.location >= 0, range.length == 0 else { return nil }
            if let rect = caretBounds(parameterized(kAXBoundsForRangeParameterizedAttribute, value)) { return rect }
        }
        // Web editors may expose valid marker bounds even when the numeric range has no geometry.
        guard let marker = attribute("AXSelectedTextMarkerRange"),
              let length = parameterized("AXLengthForTextMarkerRange", marker) as? NSNumber,
              length.doubleValue == 0 else { return nil }
        return caretBounds(parameterized("AXBoundsForTextMarkerRange", marker))
    }

    private static func caretBounds(_ raw: CFTypeRef?) -> CGRect? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect),
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.width <= 8, rect.height >= 1, rect.height <= 200 else { return nil }
        return rect
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
