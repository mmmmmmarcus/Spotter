import Foundation
@preconcurrency import ApplicationServices

enum SelectedTextReadError: Error, Equatable, Sendable {
    case accessibilityDenied
    case focusedControlUnavailable
    case selectedTextUnavailable
}

/// Stateless Accessibility reader shared by features that explicitly request the active selection.
enum SelectedTextReader {
    // Electron's documented per-app opt-in; Chromium proper (and some wrapped web views) key off the assistive flag instead, so both are set together.
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
    private static let selectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"
    private static let stringForTextMarkerRangeAttribute = "AXStringForTextMarkerRange"
    private static let webAreaRole = "AXWebArea"

    /// Single-shot synchronous read (Change Case's path): focused element, system-wide fallback, one immediate opt-in retry.
    static func read(pid: pid_t) -> Result<String, SelectedTextReadError> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityDenied) }

        let applicationElement = AXUIElementCreateApplication(pid)
        var foundFocusedElement = false
        if let result = attempt(
            application: applicationElement, pid: pid, foundFocusedElement: &foundFocusedElement)
        {
            return result
        }

        let optIn = ChromiumAccessibilityOptIn(application: applicationElement)
        defer { optIn.restore() }
        if optIn.enabledAny,
            let result = attempt(
                application: applicationElement, pid: pid,
                foundFocusedElement: &foundFocusedElement)
        {
            return result
        }

        return .failure(
            foundFocusedElement ? .selectedTextUnavailable : .focusedControlUnavailable)
    }

    /// Full asynchronous read: after opting the app into Chromium accessibility it *waits* for the tree to build — Electron apps (ChatGPT, Figma, Slack…) construct it lazily, so an immediate retry always misses.
    static func readAwaitingAccessibilityTree(pid: pid_t) async
        -> Result<String, SelectedTextReadError>
    {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityDenied) }

        let applicationElement = AXUIElementCreateApplication(pid)
        var foundFocusedElement = false
        if let result = attempt(
            application: applicationElement, pid: pid, foundFocusedElement: &foundFocusedElement)
        {
            return result
        }

        let optIn = ChromiumAccessibilityOptIn(application: applicationElement)
        defer { optIn.restore() }
        if optIn.enabledAny {
            for _ in 0..<6 {
                try? await Task.sleep(for: .milliseconds(60))
                if let result = attempt(
                    application: applicationElement, pid: pid,
                    foundFocusedElement: &foundFocusedElement)
                {
                    return result
                }
            }
        }

        return .failure(
            foundFocusedElement ? .selectedTextUnavailable : .focusedControlUnavailable)
    }

    /// One capture attempt across the three sources, cheapest first. Returns nil to signal "retry may help".
    private static func attempt(
        application: AXUIElement, pid: pid_t, foundFocusedElement: inout Bool
    ) -> Result<String, SelectedTextReadError>? {
        if let result = selectedTextResult(
            from: focusedElement(from: application), foundFocusedElement: &foundFocusedElement)
        {
            return result
        }
        if let result = selectedTextResult(
            from: systemFocusedElement(pid: pid), foundFocusedElement: &foundFocusedElement)
        {
            return result
        }
        // A web page's selection often lives on the AXWebArea, which never reports as the focused element.
        if let text = webAreaSelectedText(in: application), !text.isEmpty {
            return .success(text)
        }
        return nil
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
            let selectedText = selectedValue as? String, !selectedText.isEmpty
        {
            return selectedText
        }
        return markerRangeSelectedText(from: element)
    }

    /// Chromium/WebKit expose the selection as an opaque marker range resolved through a parameterized attribute.
    private static func markerRangeSelectedText(from element: AXUIElement) -> String? {
        var markerRange: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, selectedTextMarkerRangeAttribute as CFString, &markerRange) == .success,
            let markerRange
        else { return nil }

        var markerText: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, stringForTextMarkerRangeAttribute as CFString, markerRange, &markerText)
                == .success,
            let selectedText = markerText as? String
        else { return nil }
        return selectedText
    }

    /// Bounded breadth-first walk from the focused window looking for a web area carrying a selection.
    private static func webAreaSelectedText(in application: AXUIElement) -> String? {
        var queue: [(element: AXUIElement, depth: Int)] = [(focusedWindow(of: application), 0)]
        var visited = 0
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if visited > 250 { return nil }
            if role(of: element) == webAreaRole, let text = selectedText(from: element),
                !text.isEmpty
            {
                return text
            }
            guard depth < 12 else { continue }
            for child in children(of: element) {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    private static func focusedWindow(of application: AXUIElement) -> AXUIElement {
        var window: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application, kAXFocusedWindowAttribute as CFString, &window) == .success,
            let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return application }
        return (window as! AXUIElement)
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                == .success,
            let array = value as? [AnyObject]
        else { return [] }
        return array.compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return ($0 as! AXUIElement)
        }
    }

    private static func systemFocusedElement(pid: pid_t) -> AXUIElement? {
        guard let systemElement = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return nil
        }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(systemElement, &focusedPID) == .success, focusedPID == pid else {
            return nil
        }
        return systemElement
    }

    private static func selectedTextResult(
        from element: AXUIElement?, foundFocusedElement: inout Bool
    ) -> Result<String, SelectedTextReadError>? {
        guard let element else { return nil }
        foundFocusedElement = true
        guard let text = selectedText(from: element) else { return nil }
        return .success(text)
    }

    private static func booleanAttribute(
        _ attribute: String, from element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let number = value as? NSNumber
        else { return nil }
        return number.boolValue
    }

    private static func focusedElement(from root: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                root, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        return (focusedValue as! AXUIElement)
    }

    /// Enables both Chromium opt-in attributes and restores only the ones this capture actually flipped, so one read never leaves an app's accessibility preference under system control.
    private struct ChromiumAccessibilityOptIn {
        private let application: AXUIElement
        private let restoreManual: Bool
        private let restoreEnhanced: Bool
        let enabledAny: Bool

        init(application: AXUIElement) {
            self.application = application
            let originalManual = SelectedTextReader.booleanAttribute(
                SelectedTextReader.manualAccessibilityAttribute, from: application)
            let originalEnhanced = SelectedTextReader.booleanAttribute(
                SelectedTextReader.enhancedUserInterfaceAttribute, from: application)
            let manualEnabled = AXUIElementSetAttributeValue(
                application, SelectedTextReader.manualAccessibilityAttribute as CFString,
                kCFBooleanTrue) == .success
            let enhancedEnabled = AXUIElementSetAttributeValue(
                application, SelectedTextReader.enhancedUserInterfaceAttribute as CFString,
                kCFBooleanTrue) == .success
            restoreManual = manualEnabled && originalManual != true
            restoreEnhanced = enhancedEnabled && originalEnhanced != true
            enabledAny = manualEnabled || enhancedEnabled
        }

        func restore() {
            if restoreManual {
                _ = AXUIElementSetAttributeValue(
                    application, SelectedTextReader.manualAccessibilityAttribute as CFString,
                    kCFBooleanFalse)
            }
            if restoreEnhanced {
                _ = AXUIElementSetAttributeValue(
                    application, SelectedTextReader.enhancedUserInterfaceAttribute as CFString,
                    kCFBooleanFalse)
            }
        }
    }
}
