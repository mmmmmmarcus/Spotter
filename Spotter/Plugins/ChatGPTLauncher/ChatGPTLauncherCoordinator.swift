import AppKit
import Carbon.HIToolbox
@preconcurrency import ApplicationServices

enum ChatGPTLaunchOutcome: Sendable {
    case sent
    case draftReady
    case appDidNotLaunch
    case keyboardEventUnavailable
}

@MainActor
final class ChatGPTLauncherCoordinator {
    private var task: Task<Void, Never>?

    func send(
        prompt: String, deepLink: URL, applicationURL: URL,
        onOutcome: @escaping @MainActor (ChatGPTLaunchOutcome) -> Void
    ) {
        cancel()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [deepLink], withApplicationAt: applicationURL, configuration: configuration)

        task = Task { [weak self] in
            let pid = await Self.runningApplicationPID()
            guard !Task.isCancelled else { return }
            guard let pid else {
                onOutcome(.appDidNotLaunch)
                self?.task = nil
                return
            }

            let outcome = await ChatGPTComposerAutomation.submitWhenReady(
                prompt: prompt, pid: pid)
            guard !Task.isCancelled else { return }
            onOutcome(outcome)
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func runningApplicationPID() async -> pid_t? {
        for _ in 0..<40 {
            if Task.isCancelled { return nil }
            if let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: ChatGPTPrompt.appBundleIdentifier
            ).first {
                return application.processIdentifier
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

private enum ChatGPTComposerAutomation {
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
    private static let editableRoles = Set([
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
    ])

    static func submitWhenReady(prompt: String, pid: pid_t) async -> ChatGPTLaunchOutcome {
        let worker = Task.detached(priority: .userInitiated) {
            await waitForComposerAndSubmit(prompt: prompt, pid: pid)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func waitForComposerAndSubmit(
        prompt: String, pid: pid_t
    ) async -> ChatGPTLaunchOutcome {
        let application = AXUIElementCreateApplication(pid)
        let optIn = ChromiumAccessibilityOptIn(application: application)
        defer { optIn.restore() }

        for _ in 0..<100 {
            if Task.isCancelled { return .draftReady }
            if focusedComposerMatches(prompt: prompt, pid: pid) {
                return postReturn(to: pid) ? .sent : .keyboardEventUnavailable
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return .draftReady
    }

    /// Only a focused editable control in ChatGPT whose full value matches the deep-linked prompt is safe to submit.
    private static func focusedComposerMatches(prompt: String, pid: pid_t) -> Bool {
        guard let focused = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return false
        }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == pid else {
            return false
        }

        var candidate: AXUIElement? = focused
        for _ in 0..<5 {
            guard let element = candidate else { return false }
            if editableRoles.contains(stringAttribute(kAXRoleAttribute, from: element) ?? ""),
                let value = textValue(from: element),
                ChatGPTPrompt.matchesDraft(value, prompt: prompt)
            {
                return true
            }
            candidate = elementAttribute(kAXParentAttribute, from: element)
        }
        return false
    }

    private static func postReturn(to pid: pid_t) -> Bool {
        guard !Task.isCancelled else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        else { return false }
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    private static func focusedElement(from root: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedUIElementAttribute, from: root)
    }

    private static func elementAttribute(
        _ attribute: String, from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(
        _ attribute: String, from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func textValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        if let text = value as? String { return text }
        return (value as? NSAttributedString)?.string
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

    private struct ChromiumAccessibilityOptIn {
        private let application: AXUIElement
        private let restoreManual: Bool
        private let restoreEnhanced: Bool

        init(application: AXUIElement) {
            self.application = application
            let originalManual = ChatGPTComposerAutomation.booleanAttribute(
                ChatGPTComposerAutomation.manualAccessibilityAttribute, from: application)
            let originalEnhanced = ChatGPTComposerAutomation.booleanAttribute(
                ChatGPTComposerAutomation.enhancedUserInterfaceAttribute, from: application)
            let manualEnabled = AXUIElementSetAttributeValue(
                application,
                ChatGPTComposerAutomation.manualAccessibilityAttribute as CFString,
                kCFBooleanTrue) == .success
            let enhancedEnabled = AXUIElementSetAttributeValue(
                application,
                ChatGPTComposerAutomation.enhancedUserInterfaceAttribute as CFString,
                kCFBooleanTrue) == .success
            restoreManual = manualEnabled && originalManual != true
            restoreEnhanced = enhancedEnabled && originalEnhanced != true
        }

        func restore() {
            if restoreManual {
                _ = AXUIElementSetAttributeValue(
                    application,
                    ChatGPTComposerAutomation.manualAccessibilityAttribute as CFString,
                    kCFBooleanFalse)
            }
            if restoreEnhanced {
                _ = AXUIElementSetAttributeValue(
                    application,
                    ChatGPTComposerAutomation.enhancedUserInterfaceAttribute as CFString,
                    kCFBooleanFalse)
            }
        }
    }
}
