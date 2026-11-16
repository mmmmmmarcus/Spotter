import AppKit
import Combine

/// One target's automation state, paired with the target so the pane can list them in order.
struct AutomationReading: Identifiable, Equatable, Sendable {
    let target: AutomationTarget
    let permission: AutomationPermission

    var id: String { target.id }
}

/// One reading of every permission whose state costs a system call. Both Screen Recording answers
/// are kept rather than collapsed, because the diagnostics line has to say which one spoke.
struct PermissionsReading: Equatable, Sendable {
    var accessibilityTrusted = false
    var screenRecordingPreflight = false
    var screenRecordingWindowProbe = false
    var automation: [AutomationReading] = []

    /// Either probe saying yes is a grant: the preflight is authoritative when it answers `true`,
    /// and the window probe is the only one that can notice a grant made while Spotter runs.
    var screenRecordingGranted: Bool { screenRecordingPreflight || screenRecordingWindowProbe }
}

/// Reads the permission states that macOS exposes no change notification for, off the main actor,
/// and only while somebody is watching. Accessibility is the exception that does post one, so it is
/// observed rather than polled. Owned by `AppCore` because the startup snapshot and the diagnostics
/// line outlive any one Settings window.
@MainActor
final class PermissionsMonitor: ObservableObject {
    @Published private(set) var reading = PermissionsReading()

    /// macOS posts this when the Accessibility list changes, which is what lets `AXIsProcessTrusted`
    /// be re-read instead of polled. Removing Spotter from the list outright posts nothing; the
    /// Hyper Key's tap-health watchdog is what covers that.
    private static let accessibilityChanged = Notification.Name("com.apple.accessibility.api")
    /// Slow enough that the per-target automation reads stay invisible, quick enough that a grant
    /// made in System Settings lands while the user is still looking at the pane.
    private static let pollInterval: TimeInterval = 2

    private var accessibilityToken: NotificationToken?
    private var pollTimer: Timer?
    private var watchers = 0
    private var isRefreshing = false
    private var loggedSummary: String?

    func start() {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(
            forName: Self.accessibilityChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        accessibilityToken = NotificationToken(token, center: center)
        refresh()
    }

    /// Paired with `stopWatching()` by the Permissions pane. Refcounted so two open Settings windows
    /// don't leave the poll running after one of them closes.
    func startWatching() {
        watchers += 1
        refresh()
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Only the targets this Mac actually has, so an iTerm row never appears on a Mac without iTerm.
    private var installedTargets: [AutomationTarget] {
        AutomationTarget.all.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }
    }

    func refresh() {
        // A poll tick arriving while the previous read is still out would stack detached work.
        guard !isRefreshing else { return }
        isRefreshing = true
        let targets = installedTargets
        Task { [weak self] in
            let fresh = await Task.detached(priority: .utility) { Self.read(targets: targets) }.value
            guard let self else { return }
            isRefreshing = false
            apply(fresh)
        }
    }

    /// Everything here blocks: the AE header forbids the main thread, and the preflight costs ~12 ms
    /// whenever it answers `true`.
    private nonisolated static func read(targets: [AutomationTarget]) -> PermissionsReading {
        var fresh = PermissionsReading()
        fresh.accessibilityTrusted = Permissions.isAccessibilityTrusted()
        fresh.screenRecordingPreflight = Permissions.isScreenRecordingAllowed()
        fresh.screenRecordingWindowProbe = Permissions.screenRecordingWindowProbe()
        fresh.automation = targets.map {
            AutomationReading(
                target: $0,
                permission: Permissions.automationPermission(forBundleIdentifier: $0.bundleIdentifier))
        }
        return fresh
    }

    private func apply(_ fresh: PermissionsReading) {
        if fresh != reading { reading = fresh }
        let summary = Self.summary(for: fresh)
        guard summary != loggedSummary else { return }
        loggedSummary = summary
        AppLog.info("permissions", summary)
    }

    /// One line, written at launch and again only when something actually changes — never per poll.
    private static func summary(for reading: PermissionsReading) -> String {
        let automation =
            reading.automation
            .map { "\($0.target.name)=\(describe($0.permission))" }
            .joined(separator: ", ")
        return
            "accessibility=\(reading.accessibilityTrusted ? "granted" : "denied") "
            + "screen-recording=\(reading.screenRecordingGranted ? "granted" : "denied") "
            + "(preflight=\(reading.screenRecordingPreflight ? "yes" : "no"), "
            + "window-probe=\(reading.screenRecordingWindowProbe ? "yes" : "no")) "
            + "automation: [\(automation.isEmpty ? "none installed" : automation)]"
    }

    private static func describe(_ permission: AutomationPermission) -> String {
        switch permission {
        case .granted: "granted"
        case .denied: "denied"
        case .notDetermined: "not-asked"
        case .targetNotRunning: "not-running"
        case .unknown(let status): "unknown(\(status))"
        }
    }
}
