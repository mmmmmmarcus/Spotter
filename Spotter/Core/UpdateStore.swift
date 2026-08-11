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

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case installing
        case failed(String)
    }

    /// Explicit consent for the background check; absent reads as false and settings sync mirrors it.
    @Published private(set) var autoCheckEnabled: Bool
    @Published private(set) var status: Status = .idle

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
            let data = try await Self.fetchFeed()
            guard !requiresAutoConsent || autoCheckEnabled else {
                status = .idle
                return false
            }
            defaults.set(Date(), forKey: Self.lastCheckKey)
            if let release = UpdateFeed.latestUpdate(in: data, channel: channel, current: current) {
                status = .available(release)
            } else {
                status = .upToDate
            }
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
        guard case .available(let release) = status, let zipURL = release.zipAssetURL else { return }
        status = .installing
        let installedURL = Bundle.main.bundleURL
        do {
            try await Self.downloadAndInstall(zipURL: zipURL, over: installedURL)
            // Relaunch after this process exits; the opener outlives us.
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/bin/sh")
            opener.arguments = ["-c", "sleep 1; /usr/bin/open \"\(installedURL.path)\""]
            try opener.run()
            terminateForRelaunch?()
        } catch let error as UpdateError {
            status = .failed(error.localizedDescription)
            AppLog.error("updates", "Install failed: \(error.localizedDescription)")
        } catch {
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

    private nonisolated static func fetchFeed() async throws -> Data {
        var request = URLRequest(url: feedURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badFeed
        }
        return data
    }

    /// Off-main by way of `nonisolated async`; only plain values cross back.
    private nonisolated static func downloadAndInstall(zipURL: URL, over installedURL: URL)
        async throws
    {
        let (tempZip, response) = try await session.download(from: zipURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badDownload
        }

        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent(
            "spotter-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        defer { try? fm.removeItem(at: tempZip) }

        // ditto preserves the bundle structure, permissions and signatures exactly.
        try await runProcess("/usr/bin/ditto", ["-x", "-k", tempZip.path, stage.path])
        guard
            let newApp = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.noAppInArchive }

        try verifySignature(of: newApp, matching: installedURL)

        // Stage the copy next to the destination, then remove-and-rename so the swap window is one directory rename, not a long cross-volume copy. Never delete the working install before its replacement is fully staged beside it.
        let sibling = installedURL.deletingLastPathComponent()
            .appendingPathComponent(".update-\(UUID().uuidString)-" + installedURL.lastPathComponent)
        do {
            try fm.copyItem(at: newApp, to: sibling)
        } catch {
            try? fm.removeItem(at: sibling)
            throw UpdateError.installFailed(error.localizedDescription)
        }
        do {
            try fm.removeItem(at: installedURL)
        } catch {
            try? fm.removeItem(at: sibling)
            throw UpdateError.installFailed(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: sibling, to: installedURL)
        } catch {
            // The old bundle is already gone; the staged copy is the only Spotter left — leave it and say where it is.
            throw UpdateError.installFailed(
                "The new version could not take the old one's place; it was left at \(sibling.path).")
        }
    }

    /// The trust anchor: the new bundle must satisfy the running app's designated requirement or it is not installed.
    private nonisolated static func verifySignature(of newApp: URL, matching current: URL) throws {
        var currentCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(current as CFURL, [], &currentCode) == errSecSuccess,
            let currentCode
        else { throw UpdateError.signatureMismatch }
        var requirement: SecRequirement?
        guard
            SecCodeCopyDesignatedRequirement(currentCode, [], &requirement) == errSecSuccess,
            let requirement
        else { throw UpdateError.signatureMismatch }
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess,
            let newCode
        else { throw UpdateError.signatureMismatch }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else {
            throw UpdateError.signatureMismatch
        }
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
