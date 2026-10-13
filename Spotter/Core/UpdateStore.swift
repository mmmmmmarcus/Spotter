import Combine
import Foundation
import Security

enum UpdateError: LocalizedError {
    case badFeed
    case badDownload
    case noAppInArchive
    case signatureMismatch
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .badFeed: "Couldn't reach GitHub — check your connection."
        case .badDownload: "The update download failed."
        case .noAppInArchive: "The downloaded update did not contain Spotter.app."
        case .signatureMismatch:
            "The downloaded update is not signed with this Spotter's identity, so it was not installed."
        case .installFailed(let detail): "Installing the update failed: \(detail)"
        }
    }
}

/// Checks GitHub Releases for a newer build and installs it in place. Networked, so it follows
/// `CurrencyRateStore`'s shape: the daily automatic check ships off behind explicit consent
/// mirrored by settings sync, while Check for Updates is itself the user action. The installer refuses any
/// bundle whose code signature does not satisfy the running app's designated requirement, then
/// swaps `/Applications/Spotter.app` and relaunches — the same replace-and-relaunch contract local
/// builds follow, so the Accessibility grant survives.
@MainActor
final class UpdateStore: ObservableObject {
    static let provider = "GitHub"
    static let providerURL = URL(string: "https://github.com/mmmmmmarcus/Spotter/releases")!
    private nonisolated static let feedURL = URL(
        string: "https://api.github.com/repos/mmmmmmarcus/Spotter/releases?per_page=10")!
    /// Daily, like the currency table: releases are far rarer than that.
    static let checkInterval: TimeInterval = 24 * 3600
    private static let retryInterval: TimeInterval = 6 * 3600

    typealias Status = UpdateStatus

    /// Explicit consent for the background check; absent reads as false and settings sync mirrors it.
    @Published private(set) var autoCheckEnabled: Bool
    @Published private(set) var status: Status = .idle
    @Published private(set) var availableRelease: UpdateRelease?
    @Published private(set) var latestRelease: UpdateRelease?
    @Published private(set) var installProgress: UpdateInstallProgress?
    private var installationID: UUID?

    var presentation: UpdatePresentation {
        UpdatePresentation(status: status, release: availableRelease, progress: installProgress)
    }

    /// Wired by `AppCore.start()` to `NSApp.terminate` so the store stays AppKit-free and shutdown hooks (Hyper Key remap cleanup) still run before the relaunch.
    var terminateForRelaunch: (() -> Void)?

    private static let consentKey = "update.auto-check"
    private static let lastCheckKey = "update.last-check"
    private let defaults = UserDefaults.standard
    private var pump: Task<Void, Never>?

    init() {
        autoCheckEnabled = defaults.bool(forKey: Self.consentKey)
    }

    var currentVersion: SemanticVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(SemanticVersion.init)
    }

    var channel: UpdateChannel {
        (Bundle.main.bundleIdentifier ?? "").contains("beta") ? .beta : .stable
    }

    /// The Settings toggle's only entry point, called after the user accepts the consent dialog.
    func setAutoCheck(_ enabled: Bool) {
        guard enabled != autoCheckEnabled else { return }
        autoCheckEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        if enabled {
            start()
        } else {
            pump?.cancel()
            pump = nil
        }
    }

    /// No consent, no loop — `AppCore.start()` calls this unconditionally.
    func start() {
        guard autoCheckEnabled else { return }
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self, self.autoCheckEnabled {
                let last = self.defaults.object(forKey: Self.lastCheckKey) as? Date
                let age = max(0, last.map { Date().timeIntervalSince($0) } ?? .infinity)
                guard age >= Self.checkInterval else {
                    try? await Task.sleep(for: .seconds(Self.checkInterval - age))
                    continue
                }
                let ok = await self.check(requiresAutoConsent: true)
                try? await Task.sleep(for: .seconds(ok ? Self.checkInterval : Self.retryInterval))
            }
        }
    }

    /// Manual Check for Updates — the click is the consent for this one request.
    func checkNow() async {
        _ = await check(requiresAutoConsent: false)
    }

    @discardableResult
    private func check(requiresAutoConsent: Bool) async -> Bool {
        guard !requiresAutoConsent || autoCheckEnabled else { return false }
        // A check or install in flight must not have its state stomped by another entry point.
        if case .checking = status { return true }
        if case .installing = status { return true }
        guard let current = currentVersion else { return false }
        status = .checking
        do {
            let data = try await Self.fetchJSON(from: Self.feedURL)
            try Task.checkCancellation()
            guard !requiresAutoConsent || autoCheckEnabled else {
                status = .idle
                return false
            }
            let releases = try JSONDecoder().decode([UpdateFeed.GitHubRelease].self, from: data)
            if var release = UpdateFeed.select(from: releases, channel: channel, current: current) {
                if release.zipAssetURL == nil {
                    // GitHub's releases list can lag behind its dedicated asset endpoint after publication.
                    let url = URL(string: "https://api.github.com/repos/mmmmmmarcus/Spotter/releases/\(release.id)/assets?per_page=100")!
                    let assets = try await Self.fetchJSON(from: url)
                    try Task.checkCancellation()
                    guard !requiresAutoConsent || autoCheckEnabled else {
                        status = .idle
                        return false
                    }
                    release = try UpdateFeed.resolvingAssets(assets, for: release)
                }
                availableRelease = release
                latestRelease = release
                status = .available(release)
            } else {
                availableRelease = nil
                latestRelease = UpdateFeed.latest(from: releases, channel: channel)
                status = .upToDate
            }
            defaults.set(Date(), forKey: Self.lastCheckKey)
            return true
        } catch {
            if Task.isCancelled || (requiresAutoConsent && !autoCheckEnabled) {
                status = .idle
                return false
            }
            status = .failed(UpdateError.badFeed.localizedDescription)
            AppLog.error("updates", "Feed check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Download → unzip → verify signature → swap the installed bundle → relaunch.
    func installAvailableUpdate() async {
        guard !status.isBusy, let release = availableRelease, let zipURL = release.zipAssetURL else { return }
        status = .installing
        installProgress = .downloading(nil)
        let id = UUID()
        installationID = id
        defer { installationID = nil }
        let installedURL = Bundle.main.bundleURL
        do {
            let staged = try await Self.prepareInstallation(zipURL: zipURL, over: installedURL) {
                [weak self] progress in
                Task { @MainActor in
                    guard let self, self.installationID == id, self.status == .installing,
                          self.installProgress?.accepts(progress) == true else { return }
                    self.installProgress = progress
                }
            }
            guard let terminateForRelaunch else {
                try? FileManager.default.removeItem(at: staged)
                throw UpdateError.installFailed("The app cannot quit safely for installation.")
            }
            let log = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app1")
                .appendingPathComponent("Logs/update-installer.log")
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            let ready = FileManager.default.temporaryDirectory.appendingPathComponent("spotter-update-ready-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: ready) }
            let installer = Process()
            installer.executableURL = staged.appendingPathComponent("Contents/MacOS/Spotter")
            installer.arguments = [UpdateInstaller.argument, String(ProcessInfo.processInfo.processIdentifier),
                installedURL.path, staged.path, ready.path, log.path]
            installer.standardOutput = FileHandle.nullDevice
            installer.standardError = FileHandle.nullDevice
            do {
                try installer.run()
                for _ in 0..<100 {
                    if FileManager.default.fileExists(atPath: ready.path) { break }
                    guard installer.isRunning else { throw UpdateError.installFailed("The update helper could not start. See Diagnostics.") }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard FileManager.default.fileExists(atPath: ready.path) else {
                    throw UpdateError.installFailed("The update helper did not become ready; the installed app was kept.")
                }
            } catch {
                if installer.isRunning { installer.terminate() }
                AppLog.error("updates", "Installer handoff failed. Check update-installer.log: \(error.localizedDescription)")
                throw error
            }
            installProgress = .relaunching
            AppLog.info("updates", "Installer is ready; quitting before replacing the application bundle.")
            terminateForRelaunch()
        } catch let error as UpdateError {
            installProgress = nil
            status = .failed(error.localizedDescription)
            AppLog.error("updates", "Install failed: \(error.localizedDescription)")
        } catch {
            installProgress = nil
            status = .failed(UpdateError.installFailed(error.localizedDescription).localizedDescription)
            AppLog.error("updates", "Install failed: \(error.localizedDescription)")
        }
    }

    /// Deliberately not `URLSession.shared`: cacheless, so no feed or archive copy outlives the exchange (same rule as `CurrencyRateStore`).
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private nonisolated static func fetchJSON(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badFeed
        }
        return data
    }

    // The download delegate reports actual bytes; unknown content lengths stay indeterminate.
    private nonisolated static func downloadZip(
        from zipURL: URL, progress: @escaping @Sendable (UpdateInstallProgress) -> Void
    ) async throws -> URL {
        let (tempURL, response) = try await session.download(
            for: URLRequest(url: zipURL, timeoutInterval: 60),
            delegate: UpdateDownloadProgress(report: progress))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw UpdateError.badDownload
        }
        return tempURL
    }

    /// Off-main by way of `nonisolated async`; only plain values cross back.
    private nonisolated static func prepareInstallation(
        zipURL: URL, over installedURL: URL, progress: @escaping @Sendable (UpdateInstallProgress) -> Void
    ) async throws -> URL {
        let tempZip = try await downloadZip(from: zipURL, progress: progress)
        defer { try? FileManager.default.removeItem(at: tempZip) }
        progress(.unpacking)

        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent(
            "spotter-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }

        // ditto preserves the bundle structure, permissions and signatures exactly.
        try await runProcess("/usr/bin/ditto", ["-x", "-k", tempZip.path, stage.path])
        guard
            let newApp = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.noAppInArchive }

        progress(.verifying)
        try verifySignature(of: newApp, matching: installedURL)
        progress(.installing)

        // Keep the installed path occupied; a failed exchange must leave the working bundle intact.
        let sibling = installedURL.deletingLastPathComponent()
            .appendingPathComponent(".update-\(UUID().uuidString)-" + installedURL.lastPathComponent)
        do {
            try fm.copyItem(at: newApp, to: sibling)
            try verifySignature(of: sibling, matching: installedURL)
        } catch {
            try? fm.removeItem(at: sibling)
            throw UpdateError.installFailed(error.localizedDescription)
        }
        return sibling
    }

    /// The trust anchor: the new bundle must satisfy the running app's designated requirement or it is not installed.
    private nonisolated static func verifySignature(of newApp: URL, matching current: URL) throws {
        do { try UpdateInstaller.verify(newApp, matches: current) }
        catch { throw UpdateError.signatureMismatch }
    }

    private nonisolated static func runProcess(_ path: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: UpdateError.installFailed("\(path) exited \(p.terminationStatus)"))
                }
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

/// Per-task progress delegate for the update download. The shared session stays delegate-free and
/// cacheless; this rides along on the one download task, throttling to ten publishes a second.
/// URLSession may call it on any thread; the lock bounds publication, including unknown lengths.
private final class UpdateDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private static let interval: Duration = .milliseconds(100)

    private let report: @Sendable (UpdateInstallProgress) -> Void
    private let lock = NSLock()
    private var lastReport: ContinuousClock.Instant?

    init(report: @escaping @Sendable (UpdateInstallProgress) -> Void) {
        self.report = report
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let now = ContinuousClock.now
        lock.lock()
        let due = lastReport.map { now - $0 >= Self.interval } ?? true
        if due { lastReport = now }
        lock.unlock()
        guard due else { return }
        report(.download(written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    // Required by the protocol; the async `download(for:delegate:)` hands the file to its caller.
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {}
}
