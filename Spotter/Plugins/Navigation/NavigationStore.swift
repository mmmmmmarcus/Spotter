import AppKit
@preconcurrency import ApplicationServices
import Combine

@MainActor
final class NavigationStore: ObservableObject {
    @Published private(set) var mode: NavigationMode = .windows
    @Published private(set) var results: [NavigationResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    var onResultsChanged: (([NavigationResult]) -> Void)?
    private var task: Task<Void, Never>?
    private var targetPID: pid_t?

    func prepare(_ mode: NavigationMode, target: NSRunningApplication?) {
        close()
        self.mode = mode
        targetPID = target?.processIdentifier
        results = []
        onResultsChanged?([])
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
            onResultsChanged?(snapshot.results)
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
        let work = Task.detached(priority: .userInitiated) {
            guard AXIsProcessTrusted() else {
                return Snapshot(results: [], error: "Accessibility access is required.")
            }
            switch mode {
            case .windows: return Snapshot(results: windows(), error: nil)
            case .menus:
                guard let targetPID else { return Snapshot(results: [], error: "No application was selected.") }
                return Snapshot(results: menuItems(pid: targetPID), error: nil)
            }
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
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
            pressMenu(result)
        }
    }

    @MainActor
    static func activateMenu(_ result: NavigationResult) {
        guard let app = NSRunningApplication(processIdentifier: result.processIdentifier), !app.isTerminated else { return }
        app.activate()
        Task.detached(priority: .userInitiated) { pressMenu(result) }
    }

    private static func pressMenu(_ result: NavigationResult) {
        guard AXIsProcessTrusted() else { return }
        let root = AXUIElementCreateApplication(result.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let bar = element(root, kAXMenuBarAttribute as String),
            let item = descend(bar, path: result.locator),
            string(item, kAXTitleAttribute as String).trimmingCharacters(in: .whitespacesAndNewlines) == result.title,
            (attribute(item, kAXEnabledAttribute as String) as? Bool) != false else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
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
        var remaining = 4_000
        AXUIElementSetMessagingTimeout(root, 0.15)
        walkMenus(bar, path: [], locator: [], app: app, appName: name, results: &results,
            remaining: &remaining, deadline: ProcessInfo.processInfo.systemUptime + 2)
        return results
    }

    private static func walkMenus(_ element: AXUIElement, path: [String], locator: [String], app: NSRunningApplication,
        appName: String, results: inout [NavigationResult], remaining: inout Int, deadline: TimeInterval) {
        guard remaining > 0, locator.count < 40, !Task.isCancelled,
            ProcessInfo.processInfo.systemUptime < deadline else { return }
        for (index, child) in children(element).enumerated() {
            guard remaining > 0, !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return }
            remaining -= 1
            let title = string(child, kAXTitleAttribute as String).trimmingCharacters(in: .whitespacesAndNewlines)
            let role = string(child, kAXRoleAttribute as String)
            let nextPath = title.isEmpty ? path : path + [title]
            let nextLocator = locator + [String(index), title]
            let enabled = (attribute(child, kAXEnabledAttribute as String) as? Bool) ?? true
            guard enabled else { continue }
            if role == kAXMenuItemRole as String, !title.isEmpty, children(child).isEmpty {
                results.append(NavigationResult(id: "menu-item:\(app.processIdentifier):" + nextLocator.joined(separator: "/"),
                    title: title, subtitle: nextPath.dropLast().joined(separator: " → "), appName: appName,
                    bundlePath: app.bundleURL?.path, processIdentifier: app.processIdentifier, locator: nextLocator))
            }
            walkMenus(child, path: nextPath, locator: nextLocator, app: app, appName: appName,
                results: &results, remaining: &remaining, deadline: deadline)
        }
    }

    private static func descend(_ root: AXUIElement, path: [String]) -> AXUIElement? {
        guard !path.isEmpty, path.count.isMultiple(of: 2) else { return nil }
        var current = root
        for offset in stride(from: 0, to: path.count, by: 2) {
            let candidates = children(current)
            guard let index = NavigationResults.menuIndex(index: path[offset], title: path[offset + 1],
                titles: candidates.map { string($0, kAXTitleAttribute as String).trimmingCharacters(in: .whitespacesAndNewlines) }) else { return nil }
            current = candidates[index]
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
