import AppKit
import CoreGraphics
import CoreServices
// `@preconcurrency` downgrades AX concurrency diagnostics: `kAXTrustedCheckOptionPrompt` is a mutable C global but process-constant.
@preconcurrency import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Returns current trust state and prompts the user to grant it if needed.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func isScreenRecordingAllowed() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// The second opinion `CGPreflightScreenCaptureAccess()` needs: that call caches a `false`
    /// answer for the life of the process, so a grant made while Spotter runs can never flip it.
    /// This one is live and prompt-free, at ~0.5 ms. Off the main actor, like every caller of it.
    nonisolated static func screenRecordingWindowProbe() -> Bool {
        let windows =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return PermissionsProbe.screenRecordingGranted(
            windows: windows, ownProcessID: Int(ProcessInfo.processInfo.processIdentifier))
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// The real per-target Automation state. `askUserIfNeeded: false` is genuinely prompt-free, and
    /// the answer is never cached — it flips the instant the target launches or quits. The AE header
    /// says not to call this on the main thread, hence `nonisolated` and the detached callers; a
    /// running target costs 8–15 ms.
    nonisolated static func automationPermission(forBundleIdentifier bundleID: String)
        -> AutomationPermission
    {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return .unknown(0) }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        return PermissionsProbe.automationPermission(for: status)
    }

    @MainActor
    static func openAccessibilitySettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openAutomationSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Toggling Bluetooth can fail on a permission Spotter never requests process-wide, so the
    /// failure alert needs somewhere to send the user even though the pane carries no Bluetooth row.
    @MainActor
    static func openBluetoothSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openCalendarSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openLocationSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            )
        else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func openScreenRecordingSettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
