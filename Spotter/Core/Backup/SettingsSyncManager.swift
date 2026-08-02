import Combine
import Foundation

/// Keeps the native settings backup hot across any user-selected JSON path, including iCloud Drive.
@MainActor
final class SettingsSyncManager: ObservableObject {
    private enum Key {
        static let filePath = "settings-sync.file-path"
        static let enabled = "settings-sync.enabled"
    }

    @Published private(set) var fileURL: URL?
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?

    private weak var core: AppCore?
    private let defaults: UserDefaults
    private let io = SettingsSyncFileIO()
    private var revision = SettingsSyncRevision()
    private var watcher: SettingsSyncFileWatcher?
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

    var isICloudLocation: Bool {
        fileURL.map { FileManager.default.isUbiquitousItem(at: $0) } ?? false
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

    func connectExisting(_ url: URL) {
        Task { await connectExistingNow(url.standardizedFileURL) }
    }

    func create(at url: URL) {
        Task { await createNow(at: url.standardizedFileURL) }
    }

    func setEnabled(_ enabled: Bool) {
        guard fileURL != nil, enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        errorMessage = nil
        if enabled {
            startWatching()
            scheduleReload()
        } else {
            stopWatching()
        }
    }

    func disconnect() {
        stopWatching()
        fileURL = nil
        isEnabled = false
        revision = SettingsSyncRevision()
        lastSyncedAt = nil
        errorMessage = nil
        defaults.removeObject(forKey: Key.filePath)
        defaults.removeObject(forKey: Key.enabled)
    }

    private func connectExistingNow(_ url: URL) async {
        isWorking = true
        errorMessage = nil
        do {
            let data = try await io.read(from: url)
            let backup = try SettingsBackup(json: data)
            guard let core else { throw CocoaError(.userCancelled) }
            stopWatching()
            isApplyingRemote = true
            _ = backup.apply(to: core)
            isApplyingRemote = false
            let effectiveData = try SettingsBackup.gather(from: core).encoded()
            configure(url: url, revisionData: effectiveData)
            if effectiveData != data { try await io.write(effectiveData, to: url) }
            lastSyncedAt = Date()
        } catch {
            isApplyingRemote = false
            errorMessage = "Couldn’t connect: " + error.localizedDescription
        }
        isWorking = false
    }

    private func createNow(at url: URL) async {
        guard let core else { return }
        isWorking = true
        errorMessage = nil
        do {
            let data = try SettingsBackup.gather(from: core).encoded()
            try await io.write(data, to: url)
            stopWatching()
            configure(url: url, revisionData: data)
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Couldn’t create the sync file: " + error.localizedDescription
        }
        isWorking = false
    }

    private func configure(url: URL, revisionData: Data) {
        fileURL = url
        isEnabled = true
        revision = SettingsSyncRevision()
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
            core.favorites.objectWillChange.eraseToAnyPublisher(),
            core.visibility.objectWillChange.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(publishers)
            .sink { [weak self] in self?.scheduleSave() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.scheduleSave() }
            .store(in: &cancellables)
        core.plugins.onEnabledStatesChanged = { [weak self] in self?.scheduleSave() }
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
            let data = try SettingsBackup.gather(from: core).encoded()
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
            let backup = try SettingsBackup(json: data)
            isWorking = true
            errorMessage = nil
            isApplyingRemote = true
            _ = backup.apply(to: core)
            isApplyingRemote = false
            let effectiveData = try SettingsBackup.gather(from: core).encoded()
            revision.record(effectiveData)
            if effectiveData != data { try await io.write(effectiveData, to: fileURL) }
            lastSyncedAt = Date()
            isWorking = false
        } catch {
            isApplyingRemote = false
            isWorking = false
            errorMessage = "Couldn’t read settings: " + error.localizedDescription
        }
    }

    private func startWatching() {
        guard watcher == nil, let fileURL, isEnabled else { return }
        watcher = SettingsSyncFileWatcher(url: fileURL) { [weak self] in
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
