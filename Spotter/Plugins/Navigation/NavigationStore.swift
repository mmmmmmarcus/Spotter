import AppKit
@preconcurrency import ApplicationServices
import Combine

@MainActor
final class NavigationStore: ObservableObject {
    @Published private(set) var mode: NavigationMode = .windows
    @Published private(set) var results: [NavigationResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    private var targetPID: pid_t?

    func prepare(_ mode: NavigationMode, target: NSRunningApplication?) {
        self.mode = mode
        targetPID = target?.processIdentifier
        results = []
        errorMessage = nil
    }

    func refresh() {
        task?.cancel()
        isLoading = true
        errorMessage = nil
        let mode = mode
        let targetPID = targetPID
        task = Task { [weak self] in
            let snapshot = await NavigationReader.snapshot(mode: mode, targetPID: targetPID)
            guard !Task.isCancelled, let self, self.mode == mode else { return }
            isLoading = false
            results = snapshot.results
            errorMessage = snapshot.error
        }
    }

    func activate(id: String) {
        guard let result = results.first(where: { $0.id == id }) else { return }
        NavigationReader.activate(result, mode: mode)
    }

    func close() {
        task?.cancel()
        task = nil
        isLoading = false
    }
}

enum NavigationReader {
    struct Snapshot: Sendable {
        let results: [NavigationResult]
        let error: String?
    }

    static func snapshot(mode: NavigationMode, targetPID: pid_t?) async -> Snapshot {
        await Task.detached(priority: .userInitiated) {
            guard AXIsProcessTrusted() else {
                return Snapshot(results: [], error: "Accessibility access is required.")
            }
            switch mode {
            case .windows: return Snapshot(results: windows(), error: nil)
            case .menus:
                guard let targetPID else { return Snapshot(results: [], error: "No application was selected.") }
                return Snapshot(results: menuItems(pid: targetPID), error: nil)
            }
        }.value
    }

    static func activate(_ result: NavigationResult, mode: NavigationMode) {
        let app = NSRunningApplication(processIdentifier: result.processIdentifier)
        let root = AXUIElementCreateApplication(result.processIdentifier)
        setTimeout(root)
        switch mode {
        case .windows:
            guard let windows = attribute(root, kAXWindowsAttribute as String) as? [AXUIElement],
                let index = NavigationResults.windowIndex(locator: result.locator,
                    titles: windows.map { string($0, kAXTitleAttribute as String) })
            else { return }
            let match = windows[index]
            app?.activate()
            AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(match, kAXRaiseAction as CFString)
        case .menus:
            guard let bar = element(root, kAXMenuBarAttribute as String),
                let item = descend(bar, path: result.locator)
            else { return }
            app?.activate()
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
    }

    private static func windows() -> [NavigationResult] {
        var results: [NavigationResult] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            setTimeout(root)
            guard let windows = attribute(root, kAXWindowsAttribute as String) as? [AXUIElement] else { continue }
            for (index, window) in windows.prefix(100).enumerated() {
                guard string(window, kAXRoleAttribute as String) == kAXWindowRole as String else { continue }
                let title = string(window, kAXTitleAttribute as String).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let name = app.localizedName ?? "Application"
                results.append(NavigationResult(id: "\(app.processIdentifier):\(index):\(title)",
                    title: title, subtitle: name, appName: name, bundlePath: app.bundleURL?.path,
                    processIdentifier: app.processIdentifier, locator: [String(index), title]))
            }
        }
        return results.sorted {
            if $0.appName != $1.appName { return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func menuItems(pid: pid_t) -> [NavigationResult] {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
        let root = AXUIElementCreateApplication(pid)
        setTimeout(root)
        guard let bar = element(root, kAXMenuBarAttribute as String) else { return [] }
        let name = app.localizedName ?? "Application"
        var results: [NavigationResult] = []
        walkMenus(bar, path: [], app: app, appName: name, results: &results, remaining: 4_000)
        return results
    }

    private static func walkMenus(_ element: AXUIElement, path: [String], app: NSRunningApplication,
        appName: String, results: inout [NavigationResult], remaining: Int) {
        guard results.count < remaining else { return }
        for child in children(element) {
            guard results.count < remaining else { return }
            let title = string(child, kAXTitleAttribute as String).trimmingCharacters(in: .whitespacesAndNewlines)
            let role = string(child, kAXRoleAttribute as String)
            let nextPath = title.isEmpty ? path : path + [title]
            let enabled = (attribute(child, kAXEnabledAttribute as String) as? Bool) ?? true
            if role == kAXMenuItemRole as String, enabled, !title.isEmpty,
                (attribute(child, kAXChildrenAttribute as String) as? [AXUIElement])?.isEmpty != false {
                results.append(NavigationResult(id: "\(app.processIdentifier):" + nextPath.joined(separator: "/"),
                    title: title, subtitle: nextPath.dropLast().joined(separator: " → "), appName: appName,
                    bundlePath: app.bundleURL?.path, processIdentifier: app.processIdentifier, locator: nextPath))
            }
            walkMenus(child, path: nextPath, app: app, appName: appName, results: &results, remaining: remaining)
        }
    }

    private static func descend(_ root: AXUIElement, path: [String]) -> AXUIElement? {
        var current = root
        for title in path {
            guard let next = children(current).first(where: { string($0, kAXTitleAttribute as String) == title }) else { return nil }
            current = next
        }
        return current
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func setTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, 1)
    }
}
