import AppKit
import ApplicationServices

enum QuickClipboardAnchor {
    struct Request: Sendable {
        let mouse: CGPoint
        let localCaret: CGRect?
        let processID: pid_t?
        let primaryTop: CGFloat
        let screens: [CGRect]

        func resolve() -> CGRect {
            if let localCaret, let valid = QuickClipboardAnchor.visibleCaret(localCaret, screens: screens) { return valid }
            if let processID, let quartz = QuickClipboardAnchor.externalCaret(processID: processID) {
                let rect = QuickClipboardAnchor.appKitRect(quartz: quartz, primaryTop: primaryTop)
                if let valid = QuickClipboardAnchor.visibleCaret(rect, screens: screens) { return valid }
            }
            return CGRect(origin: mouse, size: .zero)
        }
    }

    @MainActor
    static func request(application: NSRunningApplication?, mouse: CGPoint) -> Request {
        var caret: CGRect?
        if let window = NSApp.keyWindow, window.isVisible, window.isKeyWindow,
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

    private static func externalCaret(processID: pid_t) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.08)
        guard let raw = attribute(kAXFocusedUIElementAttribute, of: application),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.08)
        let role = attribute(kAXRoleAttribute, of: element) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(where: { $0 == role }),
              (attribute("AXEditable", of: element) as? NSNumber)?.boolValue != false,
              let rawRange = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(rawRange) == AXValueGetTypeID() else { return nil }
        let value = rawRange as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
              range.location >= 0, range.length == 0 else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
            value, &bounds) == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        let rectValue = bounds as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(rectValue) == .cgRect, AXValueGetValue(rectValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
