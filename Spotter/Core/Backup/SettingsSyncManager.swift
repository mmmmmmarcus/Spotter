import Combine
import Foundation

/// Keeps the native settings backup hot in the folder the user chose, including one in iCloud Drive.
@MainActor
final class SettingsSyncManager: ObservableObject {
    private enum Key {
        static let filePath = "settings-sync.file-path"
        static let enabled = "settings-sync.enabled"
    }

    /// The user chooses the folder; this is the name Spotter gives the file inside it. The stored
    /// setting stays the full path, so a setup made when the picker asked for a file keeps using
    /// exactly that file — the folder is simply read back off the path it already holds.
    static let fileName = "Spotter Settings.json"

    @Published private(set) var fileURL: URL?
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?

    private weak var core: AppCore?
    private let defaults: UserDefaults
    private let io = CoordinatedFileIO()
    private var revision = CoordinatedFileRevision()
    private var watcher: CoordinatedFileWatcher?
    private var cancellables: Set<AnyCancellable> = []
    private var workTask: Task<Void, Never>?
    private var pendingSave = false
    private var pendingReload = false
    private var savedMetadata: Data?
    private var savedClipboardRevision: Int64?
    private var isConnecting = false
    private var connectionTask: Task<Void, Never>?
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuredURL = defaults.string(forKey: Key.filePath).map(URL.init(fileURLWithPath:))
        fileURL = configuredURL
        isEnabled = defaults.bool(forKey: Key.enabled) && configuredURL != nil
    }

    var statusText: String {
        if let errorMessage { return errorMessage }
        if isWorking { return "Syncing…" }
        guard isEnabled else { return fileURL == nil ? "Not configured" : "Paused" }
        guard let lastSyncedAt else { return "Waiting for the settings file…" }
        return "Up to date · " + lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }

    func start(core: AppCore) {
        guard !hasStarted else { return }
        hasStarted = true
        self.core = core
        observeLocalChanges(core: core)
        if isEnabled {
            Task {
                if let fileURL { await io.invalidate(fileURL) }
                guard isEnabled else { return }
                startWatching()
                scheduleReload()
            }
        }
    }

    func connect(toFolder folder: URL) {
        let url = folder.standardizedFileURL.appending(path: Self.fileName)
        let previous = connectionTask
        previous?.cancel()
        connectionTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await connectNow(url)
        }
    }

    /// Turning sync off *is* disconnecting, so there is no separate Disconnect control: the watcher
    /// stops, the file presenter and its directory source are released, the recorded revision is
    /// dropped and the stored path goes with them. Nothing keeps a claim on a file the user has
    /// stepped away from.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            // Only reachable from a path an older build left paused; the switch is disabled otherwise.
            guard fileURL != nil else { return }
            isEnabled = true
            defaults.set(true, forKey: Key.enabled)
            errorMessage = nil
            Task {
                if let fileURL { await io.invalidate(fileURL) }
                guard isEnabled else { return }
                startWatching()
                scheduleReload()
            }
        } else {
            connectionTask?.cancel()
            stopWatching()
            fileURL = nil
            isEnabled = false
            revision = CoordinatedFileRevision()
            lastSyncedAt = nil
            errorMessage = nil
            defaults.removeObject(forKey: Key.filePath)
            defaults.removeObject(forKey: Key.enabled)
        }
    }

    /// Join the settings file already in the chosen folder, or write a new one there. Only a read
    /// that fails *because nothing is there* may create: every other failure means the file may well
    /// exist and simply cannot be reached right now, and creating over it would destroy it.
    private func connectNow(_ url: URL) async {
        isConnecting = true
        stopWatching()
        await workTask?.value
        defer {
            isConnecting = false
            isWorking = false
            if isEnabled {
                startWatching()
                scheduleReload()
            }
        }
        isWorking = true
        errorMessage = nil
        do {
            let data = try await io.read(from: url)
            try await join(url: url, data: data)
        } catch is CancellationError {
        } catch {
            if Self.isMissingFile(error) {
                await create(at: url)
            } else {
                errorMessage = "Couldn’t connect: " + error.localizedDescription
                AppLog.error("settings-sync", "Couldn’t connect: " + error.localizedDescription)
            }
        }
        isWorking = false
    }

    private func join(url: URL, data: Data) async throws {
        let backup = try await SettingsBackup.decodedOffMain(data)
        guard let core else { throw CocoaError(.userCancelled) }
        stopWatching()
        await workTask?.value
        try Task.checkCancellation()
        _ = await backup.apply(to: core, mode: .replace, notes: .exclude)
        let captured = try await capture(core: core)
        let effectiveData = try await captured.backup.encodedOffMain()
        try Task.checkCancellation()
        if effectiveData != data { try await io.write(effectiveData, to: url) }
        try Task.checkCancellation()
        let fingerprint = await CoordinatedFileRevision.fingerprint(effectiveData)
        try Task.checkCancellation()
        remember(captured)
        configure(url: url, revision: fingerprint)
        lastSyncedAt = Date()
    }

    private func create(at url: URL) async {
        guard let core else { return }
        do {
            stopWatching()
            await workTask?.value
            let captured = try await capture(core: core)
            let data = try await captured.backup.encodedOffMain()
            try await io.write(data, to: url)
            try Task.checkCancellation()
            let fingerprint = await CoordinatedFileRevision.fingerprint(data)
            try Task.checkCancellation()
            remember(captured)
            configure(url: url, revision: fingerprint)
            lastSyncedAt = Date()
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn’t create the sync file: " + error.localizedDescription
            AppLog.error(
                "settings-sync", "Couldn’t create the sync file: " + error.localizedDescription)
        }
    }

    /// "There is no file here" and "this file cannot be reached" are different answers, and only the
    /// first is a fact about the user's configuration. An unmounted volume, a permissions refusal or
    /// an iCloud item that has not materialized all read as unknown, which is treated as
    /// configured-and-unavailable: the setting is kept, the condition is reported, and the watcher
    /// tries again.
    private static func isMissingFile(_ error: Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError
        case NSPOSIXErrorDomain:
            return error.code == Int(ENOENT)
        default:
            return false
        }
    }

    private func configure(url: URL, revision: CoordinatedFileRevision) {
        fileURL = url
        isEnabled = true
        self.revision = revision
        defaults.set(url.path, forKey: Key.filePath)
        defaults.set(true, forKey: Key.enabled)
        startWatching()
    }

    private func observeLocalChanges(core: AppCore) {
        let publishers: [AnyPublisher<Void, Never>] = [
            core.settings.objectWillChange.eraseToAnyPublisher(),
            core.hotKeys.objectWillChange.eraseToAnyPublisher(),
            core.customCommands.objectWillChange.eraseToAnyPublisher(),
            core.aiCommands.objectWillChange.eraseToAnyPublisher(),
            core.favorites.objectWillChange.eraseToAnyPublisher(),
            core.visibility.objectWillChange.eraseToAnyPublisher(),
            core.quicklinks.objectWillChange.eraseToAnyPublisher(),
            core.clipboardStore.objectWillChange.eraseToAnyPublisher(),
            core.calcHistory.objectWillChange.eraseToAnyPublisher(),
            core.aiChat.$sessions.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            core.aiChat.$currentID.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            core.backgroundTasks.objectWillChange.eraseToAnyPublisher(),
            core.frequentEmoji.objectWillChange.eraseToAnyPublisher(),
            core.launcherRanking.objectWillChange.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scheduleSave() }
            .store(in: &cancellables)
        // Compare the exported metadata before collecting clipboard blobs; device-local defaults are not sync changes.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSave() }
            .store(in: &cancellables)
    }

    private struct Capture {
        var backup: SettingsBackup
        let metadata: Data
        let clipboardRevision: Int64
    }

    private func capture(core: AppCore) async throws -> Capture {
        let backup = SettingsBackup.gatherMetadata(from: core)
        let clipboardRevision = core.clipboardStore.syncRevision
        let metadata = try await backup.encodedOffMain()
        try Task.checkCancellation()
        var captured = Capture(backup: backup, metadata: metadata, clipboardRevision: clipboardRevision)
        captured.backup.clipboardHistory = await core.clipboardStore.syncSnapshot()
        try Task.checkCancellation()
        return captured
    }

    private func remember(_ captured: Capture) {
        savedMetadata = captured.metadata
        savedClipboardRevision = captured.clipboardRevision
    }

    private func scheduleSave() {
        guard isEnabled, fileURL != nil else { return }
        pendingSave = true
        startWork()
    }

    private func scheduleReload() {
        guard isEnabled, fileURL != nil else { return }
        pendingReload = true
        startWork()
    }

    private func startWork() {
        guard workTask == nil, !isConnecting else { return }
        workTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, isEnabled, pendingReload || pendingSave {
                do {
                    try await Task.sleep(for: .milliseconds(pendingReload ? 250 : 600))
                } catch { break }
                if pendingReload {
                    pendingReload = false
                    await reloadNow()
                } else {
                    pendingSave = false
                    await saveNow()
                }
            }
            workTask = nil
            if isEnabled, pendingReload || pendingSave { startWork() }
        }
    }

    private func saveNow() async {
        guard let core, let fileURL, isEnabled else { return }
        do {
            var backup = SettingsBackup.gatherMetadata(from: core)
            let clipboardRevision = core.clipboardStore.syncRevision
            let metadata = try await backup.encodedOffMain()
            try Task.checkCancellation()
            guard metadata != savedMetadata || clipboardRevision != savedClipboardRevision else { return }
            backup.clipboardHistory = await core.clipboardStore.syncSnapshot()
            let data = try await backup.encodedOffMain()
            try Task.checkCancellation()
            let fingerprint = await CoordinatedFileRevision.fingerprint(data)
            try Task.checkCancellation()
            if revision != fingerprint {
                isWorking = true
                defer { isWorking = false }
                try await io.write(data, to: fileURL)
                try Task.checkCancellation()
                revision = fingerprint
                lastSyncedAt = Date()
            }
            savedMetadata = metadata
            savedClipboardRevision = clipboardRevision
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = "Couldn’t save settings: " + error.localizedDescription
            AppLog.error("settings-sync", "Couldn’t save settings: " + error.localizedDescription)
        }
    }

    private func reloadNow() async {
        guard let core, let fileURL, isEnabled else { return }
        let clipboardBaseline = core.clipboardStore.synchronizationBaseline()
        do {
            guard let data = try await io.readIfChanged(from: fileURL) else { return }
            try Task.checkCancellation()
            let fingerprint = await CoordinatedFileRevision.fingerprint(data)
            try Task.checkCancellation()
            guard revision != fingerprint else { return }
            let backup = try await SettingsBackup.decodedOffMain(data)
            let local = try await capture(core: core)
            let localData = try await local.backup.encodedOffMain()
            let changes = try await backup.changes(comparedTo: local.backup)
            try Task.checkCancellation()
            isWorking = true
            defer {
                isWorking = false
            }
            _ = await changes.apply(
                to: core, mode: .replace, notes: .exclude, clipboardBaseline: clipboardBaseline)
            try Task.checkCancellation()
            let effective = try await capture(core: core)
            let effectiveData = try await effective.backup.encodedOffMain()
            try Task.checkCancellation()
            // Do not fight an older writer when its missing fields leave our effective state unchanged.
            let shouldWrite = effectiveData != data && effectiveData != localData
            if shouldWrite { try await io.write(effectiveData, to: fileURL) }
            try Task.checkCancellation()
            let effectiveRevision = shouldWrite
                ? await CoordinatedFileRevision.fingerprint(effectiveData) : fingerprint
            try Task.checkCancellation()
            revision = effectiveRevision
            remember(effective)
            lastSyncedAt = Date()
            errorMessage = nil
        } catch is CancellationError {
            await io.invalidate(fileURL)
        } catch {
            await io.invalidate(fileURL)
            errorMessage = "Couldn’t read settings: " + error.localizedDescription
            AppLog.error("settings-sync", "Couldn’t read settings: " + error.localizedDescription)
        }
    }

    private func startWatching() {
        guard watcher == nil, let fileURL, isEnabled else { return }
        watcher = CoordinatedFileWatcher(url: fileURL) { [weak self] in
            self?.scheduleReload()
        }
    }

    private func stopWatching() {
        workTask?.cancel()
        pendingSave = false
        pendingReload = false
        savedMetadata = nil
        savedClipboardRevision = nil
        watcher?.stop()
        watcher = nil
    }
}
