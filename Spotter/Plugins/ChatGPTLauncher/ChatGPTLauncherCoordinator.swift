import AppKit
import Carbon.HIToolbox
@preconcurrency import ApplicationServices

enum ChatGPTLaunchOutcome: Sendable {
    case sent
    case chatModeUnavailable
    case deepLinkUnavailable
    case draftNotVerified
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
        NSWorkspace.shared.openApplication(
            at: applicationURL, configuration: configuration
        ) { _, _ in }

        task = Task { [weak self] in
            let pid = await Self.runningApplicationPID()
            guard !Task.isCancelled else { return }
            guard let pid else {
                onOutcome(.appDidNotLaunch)
                self?.task = nil
                return
            }

            guard await ChatGPTComposerAutomation.switchToChat(pid: pid) else {
                guard !Task.isCancelled else { return }
                onOutcome(.chatModeUnavailable)
                self?.task = nil
                return
            }
            guard !Task.isCancelled else { return }

            do {
                _ = try await NSWorkspace.shared.open(
                    [deepLink], withApplicationAt: applicationURL, configuration: configuration)
            } catch {
                guard !Task.isCancelled else { return }
                onOutcome(.deepLinkUnavailable)
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
    private static let buttonRole = kAXButtonRole as String
    private static let groupRole = kAXGroupRole as String

    static func switchToChat(pid: pid_t) async -> Bool {
        let worker = Task.detached(priority: .userInitiated) {
            await waitForChatMode(pid: pid)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

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
            if Task.isCancelled { return .draftNotVerified }
            if focusedComposerMatches(prompt: prompt, pid: pid) {
                return postReturn(to: pid) ? .sent : .keyboardEventUnavailable
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return .draftNotVerified
    }

    private static func waitForChatMode(pid: pid_t) async -> Bool {
        let application = AXUIElementCreateApplication(pid)
        let optIn = ChromiumAccessibilityOptIn(application: application)
        defer { optIn.restore() }

        for attempt in 0..<50 {
            if Task.isCancelled { return false }
            if focusedChatModeIsSelected(pid: pid) { return true }
            if attempt.isMultiple(of: 10),
                !postKey(keyCode: CGKeyCode(kVK_ANSI_1), flags: .maskControl, to: pid)
            {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static func focusedComposerMatches(prompt: String, pid: pid_t) -> Bool {
        guard let focused = focusedElement(ownedBy: pid) else { return false }

        var candidate: AXUIElement? = focused
        for _ in 0..<5 {
            guard let element = candidate else { return false }
            if editableRoles.contains(stringAttribute(kAXRoleAttribute, from: element) ?? ""),
                let value = textValue(from: element),
                ChatGPTPrompt.matchesDraft(value, prompt: prompt)
            {
                return chatModeIsSelected(near: focused)
            }
            candidate = elementAttribute(kAXParentAttribute, from: element)
        }
        return false
    }

    private static func focusedChatModeIsSelected(pid: pid_t) -> Bool {
        guard let focused = focusedElement(ownedBy: pid) else { return false }
        return chatModeIsSelected(near: focused)
    }

    private static func focusedElement(ownedBy pid: pid_t) -> AXUIElement? {
        guard let focused = focusedElement(from: AXUIElementCreateSystemWide()) else {
            return nil
        }
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == pid else {
            return nil
        }
        return focused
    }

    /// ChatGPT renders Chat then Work as two aria-pressed buttons inside one composer-mode group.
    private static func chatModeIsSelected(near focused: AXUIElement) -> Bool {
        var ancestor: AXUIElement? = focused
        for _ in 0..<9 {
            guard let element = ancestor else { return false }
            let selections = modeSelections(in: element, maximumDepth: 6)
            if !selections.isEmpty {
                return selections.count == 1
                    && ChatGPTComposerMode.isChat(pressedStates: selections[0])
            }
            ancestor = elementAttribute(kAXParentAttribute, from: element)
        }
        return false
    }

    private static func modeSelections(
        in root: AXUIElement, maximumDepth: Int
    ) -> [[Bool]] {
        var queue = elementArrayAttribute(kAXChildrenAttribute, from: root).map { ($0, 1) }
        var index = 0
        var visited = 0
        var selections: [[Bool]] = []

        while index < queue.count, visited < 500 {
            let (element, depth) = queue[index]
            index += 1
            visited += 1

            if stringAttribute(kAXRoleAttribute, from: element) == groupRole,
                let selection = twoButtonSelection(in: element)
            {
                selections.append(selection)
            }
            if depth < maximumDepth {
                queue.append(
                    contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element)
                        .map { ($0, depth + 1) })
            }
        }
        return selections
    }

    private static func twoButtonSelection(in group: AXUIElement) -> [Bool]? {
        var queue = elementArrayAttribute(kAXChildrenAttribute, from: group).map { ($0, 1) }
        var index = 0
        var states: [Bool] = []

        while index < queue.count, states.count <= 2 {
            let (element, depth) = queue[index]
            index += 1
            if stringAttribute(kAXRoleAttribute, from: element) == buttonRole,
                let pressed = pressedState(of: element)
            {
                states.append(pressed)
            }
            if depth < 3 {
                queue.append(
                    contentsOf: elementArrayAttribute(kAXChildrenAttribute, from: element)
                        .map { ($0, depth + 1) })
            }
        }
        return states.count == 2 && states.filter({ $0 }).count == 1 ? states : nil
    }

    private static func pressedState(of element: AXUIElement) -> Bool? {
        booleanAttribute(kAXSelectedAttribute, from: element)
            ?? booleanAttribute(kAXValueAttribute, from: element)
    }

    private static func postReturn(to pid: pid_t) -> Bool {
        postKey(keyCode: CGKeyCode(kVK_Return), flags: [], to: pid)
    }

    private static func postKey(
        keyCode: CGKeyCode, flags: CGEventFlags, to pid: pid_t
    ) -> Bool {
        guard !Task.isCancelled else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(
                keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
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

    private static func elementArrayAttribute(
        _ attribute: String, from element: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let elements = value as? [AXUIElement]
        else { return [] }
        return elements
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
