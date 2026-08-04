import AppKit
import Combine

/// Owns the one `caffeinate` child process that keeps the Mac awake, plus the menu-bar title.
/// `AppCore` owns the single instance.
///
/// `caffeinate` is a system binary that holds a power assertion for as long as it runs, so the
/// state *is* the process: stopping means terminating it, and the assertion dies with Spotter — a
/// crash can never leave the Mac permanently awake.
@MainActor
final class CoffeeManager: ObservableObject {
    @Published private(set) var state: CoffeeState = .off
    @Published var options = CoffeeOptions() {
        didSet {
            guard options != oldValue else { return }
            persistOptions()
            // Flags only take effect on a new process, so restart an active session to apply them.
            restartForOptionChange()
        }
    }

    private var process: Process?
    private var expiry: Date?
    private var tick: Task<Void, Never>?
    private static let displayKey = "coffee.keeps-display-awake"
    private static let diskKey = "coffee.keeps-disk-awake"

    init() {
        let defaults = UserDefaults.standard
        options = CoffeeOptions(
            keepsDisplayAwake: defaults.object(forKey: Self.displayKey) == nil
                || defaults.bool(forKey: Self.displayKey),
            keepsDiskAwake: defaults.bool(forKey: Self.diskKey))
    }

    // The child would otherwise outlive a recreated manager and hold the assertion forever.
    isolated deinit {
        process?.terminate()
        tick?.cancel()
    }

    var isOn: Bool { state.isOn }

    /// Remaining time for a timed session, refreshed by the ticker so a status row can count down.
    var remaining: String? {
        guard case .until(let end) = state else { return nil }
        return CoffeeFormatter.remaining(until: end)
    }

    func caffeinate() {
        start(seconds: nil, pid: nil, state: .indefinite)
    }

    func caffeinate(for duration: CoffeeDuration) {
        let end = Date().addingTimeInterval(TimeInterval(duration.seconds))
        start(seconds: duration.seconds, pid: nil, state: .until(end))
    }

    /// Keeps the Mac awake exactly as long as `app` runs — `caffeinate -w` exits with the watched PID.
    func caffeinate(whileRunning app: NSRunningApplication) {
        guard let name = app.localizedName else { return }
        start(seconds: nil, pid: app.processIdentifier, state: .whileRunning(appName: name))
    }

    func decaffeinate() {
        process?.terminate()
        process = nil
        expiry = nil
        tick?.cancel()
        tick = nil
        state = .off
    }

    func toggle() {
        isOn ? decaffeinate() : caffeinate()
    }

    private func start(seconds: Int?, pid: Int32?, state newState: CoffeeState) {
        // One assertion at a time: a second caffeinate would leak the first.
        decaffeinate()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = options.arguments(seconds: seconds, pid: pid)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // The process ends on its own for -t and -w; reflect that in the UI rather than showing a stale "on".
        process.terminationHandler = { _ in
            Task { @MainActor [weak self] in
                guard let self, self.process != nil else { return }
                self.decaffeinate()
            }
        }
        do {
            try process.run()
        } catch {
            state = .off
            return
        }
        self.process = process
        state = newState
        if case .until(let end) = newState {
            expiry = end
            startTicking()
        }
    }

    /// Publishes once a second so a visible countdown stays honest; only runs for a timed session.
    private func startTicking() {
        tick?.cancel()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, case .until = self.state else { return }
                self.objectWillChange.send()
            }
        }
    }

    private func restartForOptionChange() {
        switch state {
        case .off:
            return
        case .indefinite:
            caffeinate()
        case .until(let end):
            let seconds = max(1, Int(end.timeIntervalSinceNow))
            start(seconds: seconds, pid: nil, state: .until(end))
        case .whileRunning(let appName):
            guard
                let app = NSWorkspace.shared.runningApplications.first(where: {
                    $0.localizedName == appName
                })
            else {
                decaffeinate()
                return
            }
            caffeinate(whileRunning: app)
        }
    }

    private func persistOptions() {
        UserDefaults.standard.set(options.keepsDisplayAwake, forKey: Self.displayKey)
        UserDefaults.standard.set(options.keepsDiskAwake, forKey: Self.diskKey)
    }
}
