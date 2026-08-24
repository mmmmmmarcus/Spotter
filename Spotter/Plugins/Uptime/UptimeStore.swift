import AppKit
import Combine
import Foundation

/// Backs the uptime widget: how long today's session has run, and how many keys and clicks it took.
/// `UptimeEngine` stays pure and is handed finished values; the monitors and persistence
/// live here.
///
/// Nothing here reaches the network, but watching input system-wide deserves the same treatment, so
/// it follows the consent shape the weather card uses: off until the user accepts the dialog in
/// Settings, monitors installed only while it is on, and turning it off deletes the tallies.
///
/// The counters take exactly two facts off an event — whether it was a key or a click, and whether a
/// key was an autorepeat. Key codes, characters, modifiers and click locations are never read, so
/// there is nothing retained from which typing could be reconstructed. Keep it that way.
@MainActor
final class UptimeStore: ObservableObject {
    /// Explicit user consent, persisted locally and mirrored by the trusted settings-sync file.
    @Published private(set) var isEnabled: Bool
    /// True only while enabled and untrusted: clicks still count, keys can't. The card and Settings
    /// both surface it rather than silently reporting a keyboard that looks idle.
    @Published private(set) var needsAccessibility = false

    private enum Keys {
        static let consent = "dashboard-widgets.uptime-enabled"
        static let countedDay = "dashboard-widgets.uptime-day"
        static let keys = "dashboard-widgets.uptime-keys"
        static let clicks = "dashboard-widgets.uptime-clicks"
        static let sessionStart = "dashboard-widgets.uptime-session-start"
    }

    /// Coalescing window for the tallies: a keystroke is far too often to write through, and losing
    /// at most this much on a crash costs nothing.
    private static let flushInterval: TimeInterval = 5

    private let defaults: UserDefaults
    private let calendar: Calendar

    // Deliberately not @Published: these move at typing speed, and republishing would redraw the
    // palette on every keystroke. The card is inside the dashboard's one-second `TimelineView`, which
    // re-reads them on its own tick.
    private var counts: UptimeInputCounts
    private var countedDay: Date?
    private var sessionStart: Date?
    private var isDirty = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var flushTimer: Timer?
    private var sessionTokens: [NotificationToken] = []

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
        // Absent reads as false, the only safe default for a feature that watches input.
        isEnabled = defaults.bool(forKey: Keys.consent)
        counts = UptimeInputCounts(
            keys: defaults.integer(forKey: Keys.keys), clicks: defaults.integer(forKey: Keys.clicks))
        countedDay = defaults.object(forKey: Keys.countedDay) as? Date
        sessionStart = defaults.object(forKey: Keys.sessionStart) as? Date
    }

    // The monitors capture self weakly, but a store that outlives its own teardown would keep them
    // registered with AppKit for nothing.
    isolated deinit {
        removeMonitors()
        flushTimer?.invalidate()
    }

    /// Called once from `AppCore.start()`. A no-op without consent, so it is safe unconditionally.
    func start() {
        installObserversIfNeeded()
        syncMonitorPresence()
    }

    /// What the card draws. A pure read — the day-rollover writes happen on the flush timer and in
    /// the counting path, never from inside a view body.
    func snapshot(now: Date = Date()) -> UptimeSnapshot {
        guard isEnabled else { return .empty }
        return UptimeSnapshot(
            sessionStart: UptimeEngine.carriedOverSessionStart(
                sessionStart, now: now, calendar: calendar),
            counts: UptimeEngine.carriedOverCounts(
                counts, countedDay: countedDay, now: now, calendar: calendar))
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.consent)
        // Off leaves nothing behind, the same way revoking weather consent deletes the cached reading.
        if !enabled { clearStoredCounts() }
        syncMonitorPresence()
    }

    /// Settings' "Reset Today" — clears the tallies without disturbing when the session started.
    func resetCounts() {
        counts = .zero
        countedDay = Date()
        isDirty = true
        flush()
    }

    @discardableResult
    func applyPreferences(enabled: Bool?) -> Int {
        guard let enabled else { return 0 }
        setEnabled(enabled)
        return 1
    }

    /// Called from `applicationWillTerminate`, where the flush timer won't get another turn.
    func flush() {
        guard isDirty else { return }
        isDirty = false
        defaults.set(counts.keys, forKey: Keys.keys)
        defaults.set(counts.clicks, forKey: Keys.clicks)
        defaults.set(countedDay, forKey: Keys.countedDay)
        defaults.set(sessionStart, forKey: Keys.sessionStart)
    }

    // MARK: - Counting

    /// The whole of what a counted event contributes. `isKey` and `isRepeat` are the only facts the
    /// monitors extract; the event itself never crosses into the store.
    private func record(isKey: Bool) {
        let now = Date()
        normalizeDay(now: now)
        stampSessionStart(now: now)
        if isKey {
            counts.keys += 1
        } else {
            counts.clicks += 1
        }
        countedDay = now
        isDirty = true
    }

    /// A new calendar day zeroes the tallies and drops the start stamp, so the next sign of activity
    /// begins the new session rather than midnight doing it for an unattended Mac.
    private func normalizeDay(now: Date) {
        let carriedStart = UptimeEngine.carriedOverSessionStart(
            sessionStart, now: now, calendar: calendar)
        let carriedCounts = UptimeEngine.carriedOverCounts(
            counts, countedDay: countedDay, now: now, calendar: calendar)
        guard carriedStart != sessionStart || carriedCounts != counts else { return }
        sessionStart = carriedStart
        counts = carriedCounts
        countedDay = now
        isDirty = true
    }

    /// Stamps the day's start on its first sign of activity. A sleeping display is not one: a Mac
    /// that woke for a background task at 4am must not have the user's day start there.
    private func stampSessionStart(now: Date = Date()) {
        guard isEnabled, sessionStart == nil, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else {
            return
        }
        sessionStart = now
        isDirty = true
    }

    // MARK: - Monitor lifecycle

    private func syncMonitorPresence() {
        guard isEnabled else {
            removeMonitors()
            stopFlushTimer()
            needsAccessibility = false
            return
        }
        installMonitors()
        startFlushTimer()
        let now = Date()
        normalizeDay(now: now)
        stampSessionStart(now: now)
        refreshTrust()
    }

    /// A global monitor is passive by construction — it cannot alter or swallow an event — which is
    /// why this counts through one rather than adding a fourth `CGEventTap`. The local monitor is the
    /// other half: global monitors never see events delivered to Spotter itself, so without it
    /// everything typed into the palette would go uncounted.
    private func installMonitors() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let isKey = event.type == .keyDown
            // Held keys repeat at the system rate; counting those would measure key repeat, not typing.
            guard !(isKey && event.isARepeat) else { return }
            MainActor.assumeIsolated { self?.record(isKey: isKey) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let isKey = event.type == .keyDown
            guard !(isKey && event.isARepeat) else { return event }
            MainActor.assumeIsolated { self?.record(isKey: isKey) }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func startFlushTimer() {
        guard flushTimer == nil else { return }
        flushTimer = Timer.scheduledTimer(
            withTimeInterval: Self.flushInterval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    /// Also where the day rolls over on an idle Mac: without a keystroke to trigger it, nothing else
    /// would notice midnight passing while the palette sits closed.
    private func tick() {
        guard isEnabled else { return }
        normalizeDay(now: Date())
        refreshTrust()
        flush()
    }

    /// Key events need the Accessibility grant; clicks don't. AppKit hands back a monitor token
    /// either way, so trust has to be polled — and the monitors are re-registered when it is granted,
    /// since the existing registration was made while untrusted.
    private func refreshTrust() {
        let needs = !Permissions.isAccessibilityTrusted()
        guard needs != needsAccessibility else { return }
        needsAccessibility = needs
        if !needs {
            removeMonitors()
            installMonitors()
        }
    }

    private func installObserversIfNeeded() {
        guard sessionTokens.isEmpty else { return }
        // A woken screen or a resumed session is the day's first sign of activity when the user
        // hasn't typed yet — otherwise the session would only start at the first keystroke.
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        sessionTokens = names.map { name in
            NotificationToken(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.screenDidWake() }
                }, center: center)
        }
    }

    private func screenDidWake() {
        guard isEnabled else { return }
        let now = Date()
        normalizeDay(now: now)
        stampSessionStart(now: now)
    }

    private func clearStoredCounts() {
        counts = .zero
        countedDay = nil
        sessionStart = nil
        isDirty = false
        for key in [Keys.keys, Keys.clicks, Keys.countedDay, Keys.sessionStart] {
            defaults.removeObject(forKey: key)
        }
    }
}
