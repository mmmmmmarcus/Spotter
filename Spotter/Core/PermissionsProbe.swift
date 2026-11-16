import Foundation

/// One app Spotter drives with Apple Events. Automation is granted per target, so the pane needs
/// one state per target rather than a single row that can only name the pane it is managed in.
struct AutomationTarget: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let name: String
    /// Carried here rather than chosen in the view so the pane's second group is glyphed like its
    /// first; a name alone would leave the list half-indented against the rows above it.
    let symbolName: String

    var id: String { bundleIdentifier }

    /// Every target Spotter actually sends an Apple Event to. Adding a `tell application` elsewhere
    /// without adding it here leaves a permission the pane cannot report.
    static let all: [AutomationTarget] = [
        AutomationTarget(
            bundleIdentifier: "com.apple.finder", name: "Finder", symbolName: "folder"),
        AutomationTarget(
            bundleIdentifier: "com.apple.systemevents", name: "System Events",
            symbolName: "gearshape"),
        AutomationTarget(
            bundleIdentifier: "com.apple.Music", name: "Music", symbolName: "music.note"),
        AutomationTarget(
            bundleIdentifier: "com.apple.Terminal", name: "Terminal", symbolName: "terminal"),
        AutomationTarget(
            bundleIdentifier: "com.googlecode.iterm2", name: "iTerm2", symbolName: "terminal")
    ]
}

/// What macOS reports for one automation target right now.
enum AutomationPermission: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    /// No public API reports a stored grant for an app that is not running, and launching one to
    /// find out would be worse than not knowing: Spotter sends a stopped app nothing either.
    case targetNotRunning
    case unknown(Int32)
}

/// The pure half of permission detection: the `OSStatus` an automation probe returns, and the
/// window list a Screen Recording probe reads. Both are driven from fixtures by
/// `Tools/permissions-test.swift`, so neither may reach the system itself.
enum PermissionsProbe {
    // Spelled out rather than imported: CoreServices' `MacErrors.h` would drag the whole framework
    // into a file whose whole point is that it needs nothing but Foundation.
    static let automationGrantedStatus: Int32 = 0  // noErr
    static let automationDeniedStatus: Int32 = -1743  // errAEEventNotPermitted
    static let automationConsentStatus: Int32 = -1744  // errAEEventWouldRequireUserConsent
    static let automationNotRunningStatus: Int32 = -600  // procNotFound

    static let windowLayerKey = "kCGWindowLayer"
    static let windowOwnerPIDKey = "kCGWindowOwnerPID"
    static let windowNameKey = "kCGWindowName"

    static func automationPermission(for status: Int32) -> AutomationPermission {
        switch status {
        case automationGrantedStatus: .granted
        case automationDeniedStatus: .denied
        case automationConsentStatus: .notDetermined
        case automationNotRunningStatus: .targetNotRunning
        default: .unknown(status)
        }
    }

    /// Screen Recording's second opinion. `CGWindowListCopyWindowInfo` hands back `kCGWindowName`
    /// only to a process that holds the grant, so the *key's presence* is the signal — its value is
    /// legitimately an empty string for an untitled window, and testing for a non-empty one would
    /// let WindowServer's own layer-24 "Menubar" entries read as a grant. Layer 0 and another
    /// process are what make it a normal window somebody else owns; the one false answer it can give
    /// is a "no" when nothing else has a window on screen, which is why it only ever adds to the
    /// preflight rather than replacing it.
    static func screenRecordingGranted(windows: [[String: Any]], ownProcessID: Int) -> Bool {
        for window in windows {
            guard let layer = window[windowLayerKey] as? Int, layer == 0 else { continue }
            guard let pid = window[windowOwnerPIDKey] as? Int, pid != ownProcessID else { continue }
            if window[windowNameKey] != nil { return true }
        }
        return false
    }
}
