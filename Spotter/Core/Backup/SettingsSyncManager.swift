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
    private var saveTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var isApplyingRemote = false
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
            startWatching()
            scheduleReload()
        }
    }

    func connect(toFolder folder: URL) {
        let url = folder.standardizedFileURL.appending(path: Self.fileName)
        Task { await connectNow(url) }
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
            startWatching()
            scheduleReload()
        } else {
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
        isWorking = true
        errorMessage = nil
        do {
            let data = try await io.read(from: url)
            try await join(url: url, data: data)
        } catch {
            if Self.isMissingFile(error) {
                await create(at: url)
            } else {
                isApplyingRemote = false
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
        isApplyingRemote = true
        _ = await backup.apply(to: core, mode: .replace, notes: .exclude)
        isApplyingRemote = false
        let effectiveData = try await SettingsBackup.gather(from: core, notes: .exclude)
            .encodedOffMain()
        configure(url: url, revisionData: effectiveData)
        if effectiveData != data { try await io.write(effectiveData, to: url) }
        lastSyncedAt = Date()
    }

    private func create(at url: URL) async {
        guard let core else { return }
        do {
            let data = try await SettingsBackup.gather(from: core, notes: .exclude).encodedOffMain()
            try await io.write(data, to: url)
            stopWatching()
            configure(url: url, revisionData: data)
            lastSyncedAt = Date()
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

    private func configure(url: URL, revisionData: Data) {
        fileURL = url
        isEnabled = true
        revision = CoordinatedFileRevision()
        revision.record(revisionData)
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
            core.aiChat.objectWillChange.eraseToAnyPublisher(),
            core.backgroundTasks.objectWillChange.eraseToAnyPublisher(),
            core.frequentEmoji.objectWillChange.eraseToAnyPublisher(),
            core.launcherRanking.objectWillChange.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scheduleSave() }
            .store(in: &cancellables)
        // Every defaults-backed store rides this one notification — world clock, snippets, screenshot,
        // translate, OpenRouter, updates, currency rates, the widget strip. Only the file- and
        // SQLite-backed stores above need a publisher of their own.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleSave() }
            .store(in: &cancellables)
    }

    private func scheduleSave() {
        guard isEnabled, fileURL != nil, !isApplyingRemote else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() async {
        guard let core, let fileURL, isEnabled, !isApplyingRemote else { return }
        do {
            let data = try await SettingsBackup.gather(from: core, notes: .exclude).encodedOffMain()
            guard !revision.isCurrent(data) else { return }
            isWorking = true
            errorMessage = nil
            try await io.write(data, to: fileURL)
            revision.record(data)
            lastSyncedAt = Date()
            isWorking = false
        } catch {
            isWorking = false
            errorMessage = "Couldn’t save settings: " + error.localizedDescription
            AppLog.error("settings-sync", "Couldn’t save settings: " + error.localizedDescription)
        }
    }

    private func scheduleReload() {
        guard isEnabled, fileURL != nil else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reloadNow()
        }
    }

    private func reloadNow() async {
        guard let core, let fileURL, isEnabled else { return }
        saveTask?.cancel()
        do {
            let data = try await io.read(from: fileURL)
            guard !revision.isCurrent(data) else { return }
            let backup = try await SettingsBackup.decodedOffMain(data)
            isWorking = true
            errorMessage = nil
            isApplyingRemote = true
            _ = await backup.apply(to: core, mode: .replace, notes: .exclude)
            isApplyingRemote = false
            let effectiveData = try await SettingsBackup.gather(from: core, notes: .exclude)
                .encodedOffMain()
            revision.record(effectiveData)
            if effectiveData != data { try await io.write(effectiveData, to: fileURL) }
            lastSyncedAt = Date()
            isWorking = false
        } catch {
            isApplyingRemote = false
            isWorking = false
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
        saveTask?.cancel()
        reloadTask?.cancel()
        saveTask = nil
        reloadTask = nil
        watcher?.stop()
        watcher = nil
    }
}
