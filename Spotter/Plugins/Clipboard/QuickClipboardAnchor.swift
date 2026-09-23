import AppKit
import ApplicationServices

enum QuickClipboardAnchor {
    struct Request: Sendable {
        let mouse: CGPoint
        let localCaret: CGRect?
        let processID: pid_t?
        let primaryTop: CGFloat
        let screens: [CGRect]

        func resolve(lookup: @escaping @Sendable (pid_t) async -> CGRect? = QuickClipboardAnchor.externalAnchor) async -> CGRect {
            if let localCaret, let valid = QuickClipboardAnchor.visibleCaret(localCaret, screens: screens) { return valid }
            let fallback = CGRect(origin: mouse, size: .zero)
            guard let processID, !Task.isCancelled else { return fallback }
            let (stream, continuation) = AsyncStream<CGRect>.makeStream(bufferingPolicy: .bufferingOldest(1))
            // An unresponsive AX call must not hold the menu behind a structured task-group join.
            let worker = Task.detached(priority: .userInitiated) {
                var anchor = fallback
                if let quartz = await lookup(processID) {
                    let rect = QuickClipboardAnchor.appKitRect(quartz: quartz, primaryTop: primaryTop)
                    anchor = QuickClipboardAnchor.visibleCaret(rect, screens: screens) ?? fallback
                }
                guard !Task.isCancelled else { return }
                continuation.yield(anchor)
                continuation.finish()
            }
            let deadline = Task {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
                continuation.yield(fallback)
                continuation.finish()
            }
            defer {
                worker.cancel()
                deadline.cancel()
                continuation.finish()
            }
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() ?? fallback
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

    private static func externalAnchor(processID: pid_t) async -> CGRect? {
        guard !Task.isCancelled, AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.08)
        if let rect = focusedAnchor(application: application, processID: processID) { return rect }
        var restored: [String] = []
        var accessibilityEnabled = false
        defer {
            for name in restored { AXUIElementSetAttributeValue(application, name as CFString, kCFBooleanFalse) }
        }
        // Chromium exposes its focused editor only after accessibility has been requested.
        for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            guard !Task.isCancelled else { return nil }
            if (attribute(name, of: application) as? NSNumber)?.boolValue == true {
                accessibilityEnabled = true
            } else if !Task.isCancelled, AXUIElementSetAttributeValue(application, name as CFString, kCFBooleanTrue) == .success {
                accessibilityEnabled = true
                restored.append(name)
            }
        }
        guard accessibilityEnabled else { return nil }
        // Electron builds its accessibility tree lazily; an immediate retry misses the editor.
        for _ in 0..<6 {
            do { try await Task.sleep(for: .milliseconds(8)) }
            catch { return nil }
            if let rect = focusedAnchor(application: application, processID: processID) { return rect }
        }
        return nil
    }

    private static func focusedAnchor(application: AXUIElement, processID: pid_t) -> CGRect? {
        for root in [application, AXUIElementCreateSystemWide()] {
            AXUIElementSetMessagingTimeout(root, 0.08)
            guard let raw = attribute(kAXFocusedUIElementAttribute, of: root),
                  CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let element = raw as! AXUIElement
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid == processID else { continue }
            AXUIElementSetMessagingTimeout(element, 0.08)
            if let rect = insertionAnchor(of: element) { return rect }
        }
        return nil
    }

    static func isEditableCaret(role: String?, editable: Bool?, range: CFRange) -> Bool {
        let textRole = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains { $0 == role }
        return (textRole || editable == true) && editable != false && range.location >= 0 && range.length == 0
    }

    private static func insertionAnchor(of element: AXUIElement) -> CGRect? {
        insertionAnchor(attribute: { attribute($0, of: element) }, parameterized: { name, parameter in
            var result: CFTypeRef?
            guard !Task.isCancelled, AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &result) == .success else { return nil }
            return result
        })
    }

    static func insertionAnchor(attribute: (String) -> CFTypeRef?, parameterized: (String, CFTypeRef) -> CFTypeRef?) -> CGRect? {
        let role = attribute(kAXRoleAttribute) as? String
        let editable = (attribute("AXEditable") as? NSNumber)?.boolValue
        guard isEditableCaret(role: role, editable: editable, range: CFRange(location: 0, length: 0)) else { return nil }
        var selection: CFRange?
        if let rawRange = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() {
            let value = rawRange as! AXValue
            var range = CFRange()
            guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range),
                  range.location >= 0, range.length == 0 else { return nil }
            selection = range
            if let rect = caretBounds(parameterized(kAXBoundsForRangeParameterizedAttribute, value)) { return rect }
        }
        // Web editors may expose valid marker bounds even when the numeric range has no geometry.
        guard let marker = attribute("AXSelectedTextMarkerRange"),
              let length = parameterized("AXLengthForTextMarkerRange", marker) as? NSNumber,
              length.doubleValue == 0 else { return nil }
        let rawBounds = parameterized("AXBoundsForTextMarkerRange", marker)
        if let rect = caretBounds(rawBounds) { return rect }
        guard selection?.location == 0,
              let count = attribute(kAXNumberOfCharactersAttribute) as? NSNumber,
              count.doubleValue == 0 || count.doubleValue == 1,
              let rawBounds, CFGetTypeID(rawBounds) == AXValueGetTypeID() else { return nil }
        let value = rawBounds as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(value) == .cgRect, AXValueGetValue(value, .cgRect, &rect),
              rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 8, rect.width <= 4096, rect.height >= 1, rect.height <= 600 else { return nil }
        // Empty Chromium editors (including a lone placeholder newline) expose their box, not a caret.
        return CGRect(x: rect.minX, y: rect.minY, width: 0, height: 1)
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
        guard !Task.isCancelled, AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
