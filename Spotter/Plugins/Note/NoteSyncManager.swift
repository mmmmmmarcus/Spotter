import Combine
import Foundation

@MainActor
final class NoteSyncManager: ObservableObject {
    private struct Keys {
        let filePath: String
        let enabled: String
        let migrated: String

        init(bundleID: String) {
            let prefix = bundleID + ".note-sync"
            filePath = prefix + ".file-path"
            enabled = prefix + ".enabled"
            migrated = prefix + ".separated-from-settings-v1"
        }
    }

    @Published private(set) var fileURL: URL?
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?

    private let store: NoteStore
    private let defaults: UserDefaults
    private let keys: Keys
    private let io = CoordinatedFileIO()
    private var revision = CoordinatedFileRevision()
    private var watcher: CoordinatedFileWatcher?
    private var storeCancellable: AnyCancellable?
    private var saveTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var migrationTask: Task<Void, Never>?
    private var isApplyingRemote = false
    private var isRunning = false

    init(
        store: NoteStore, defaults: UserDefaults = .standard,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.spotter.app"
    ) {
        self.store = store
        self.defaults = defaults
        keys = Keys(bundleID: bundleID)
        let configuredURL = defaults.string(forKey: keys.filePath).map(URL.init(fileURLWithPath:))
        fileURL = configuredURL
        isEnabled = defaults.bool(forKey: keys.enabled) && configuredURL != nil
    }

    var statusText: String {
        if let errorMessage { return errorMessage }
        if isWorking { return "Syncing…" }
        guard isEnabled else { return fileURL == nil ? "Not configured" : "Paused" }
        guard let lastSyncedAt else { return "Waiting for the Notes file…" }
        return "Up to date · " + lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }

    var isICloudLocation: Bool {
        fileURL.map { FileManager.default.isUbiquitousItem(at: $0) } ?? false
    }

    func start(migratingFrom settingsSyncURL: URL?) {
        guard !isRunning else { return }
        isRunning = true
        if storeCancellable == nil {
            storeCancellable = store.objectWillChange.sink { [weak self] in self?.scheduleSave() }
        }
        if isEnabled {
            startWatching()
            scheduleReload()
        } else if fileURL == nil, !defaults.bool(forKey: keys.migrated),
            let settingsSyncURL
        {
            migrateFromSettingsSync(settingsSyncURL)
        }
    }

    func stop() {
        isRunning = false
        stopWatching()
        migrationTask?.cancel()
        migrationTask = nil
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
        defaults.set(enabled, forKey: keys.enabled)
        errorMessage = nil
        if enabled, isRunning {
            startWatching()
            scheduleReload()
        } else {
            stopWatching()
        }
    }

    func disconnect() {
        stopWatching()
        migrationTask?.cancel()
        migrationTask = nil
        fileURL = nil
        isEnabled = false
        revision = CoordinatedFileRevision()
        lastSyncedAt = nil
        errorMessage = nil
        defaults.removeObject(forKey: keys.filePath)
        defaults.removeObject(forKey: keys.enabled)
        defaults.set(true, forKey: keys.migrated)
    }

    private func connectExistingNow(_ url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            let data = try await io.read(from: url)
            let document = try await NoteSyncDocument.decodedOffMain(data)
            stopWatching()
            isApplyingRemote = true
            store.replace(notes: document.notes, selectedID: document.selectedID)
            isApplyingRemote = false
            let effectiveData = try await snapshot().encodedOffMain()
            configure(url: url, revisionData: effectiveData)
            if effectiveData != data { try await io.write(effectiveData, to: url) }
            lastSyncedAt = Date()
        } catch {
            isApplyingRemote = false
            errorMessage = "Couldn’t connect: " + error.localizedDescription
            AppLog.error("note-sync", "Couldn’t connect: " + error.localizedDescription)
        }
        isWorking = false
    }

    private func createNow(at url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        do {
            let data = try await snapshot().encodedOffMain()
            try await io.write(data, to: url)
            stopWatching()
            configure(url: url, revisionData: data)
            defaults.set(true, forKey: keys.migrated)
            lastSyncedAt = Date()
        } catch {
            errorMessage = "Couldn’t create the Notes file: " + error.localizedDescription
            AppLog.error("note-sync", "Couldn’t create the Notes file: " + error.localizedDescription)
        }
        isWorking = false
    }

    private func configure(url: URL, revisionData: Data) {
        fileURL = url
        isEnabled = true
        revision = CoordinatedFileRevision()
        revision.record(revisionData)
        defaults.set(url.path, forKey: keys.filePath)
        defaults.set(true, forKey: keys.enabled)
        defaults.set(true, forKey: keys.migrated)
        if isRunning { startWatching() }
    }

    private func scheduleSave() {
        guard isRunning, isEnabled, fileURL != nil, !isApplyingRemote else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() async {
        guard let fileURL, isRunning, isEnabled, !isApplyingRemote else { return }
        do {
            let data = try await snapshot().encodedOffMain()
            guard !revision.isCurrent(data) else { return }
            isWorking = true
            errorMessage = nil
            try await io.write(data, to: fileURL)
            revision.record(data)
            lastSyncedAt = Date()
            isWorking = false
        } catch {
            isWorking = false
            errorMessage = "Couldn’t save Notes: " + error.localizedDescription
            AppLog.error("note-sync", "Couldn’t save Notes: " + error.localizedDescription)
        }
    }

    private func scheduleReload() {
        guard isRunning, isEnabled, fileURL != nil else { return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reloadNow()
        }
    }

    private func reloadNow() async {
        guard let fileURL, isRunning, isEnabled else { return }
        saveTask?.cancel()
        do {
            let data = try await io.read(from: fileURL)
            guard !revision.isCurrent(data) else { return }
            let document = try await NoteSyncDocument.decodedOffMain(data)
            isWorking = true
            errorMessage = nil
            isApplyingRemote = true
            store.replace(notes: document.notes, selectedID: document.selectedID)
            isApplyingRemote = false
            let effectiveData = try await snapshot().encodedOffMain()
            revision.record(effectiveData)
            if effectiveData != data { try await io.write(effectiveData, to: fileURL) }
            lastSyncedAt = Date()
            isWorking = false
        } catch {
            isApplyingRemote = false
            isWorking = false
            errorMessage = "Couldn’t read Notes: " + error.localizedDescription
            AppLog.error("note-sync", "Couldn’t read Notes: " + error.localizedDescription)
        }
    }

    private func migrateFromSettingsSync(_ settingsURL: URL) {
        let directory = settingsURL.deletingLastPathComponent()
        var target = directory.appendingPathComponent("Spotter Notes.json")
        if target.standardizedFileURL == settingsURL.standardizedFileURL {
            target = directory.appendingPathComponent("Spotter Notes Sync.json")
        }
        migrationTask?.cancel()
        migrationTask = Task { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: target.path) {
                await self.connectExistingNow(target)
            } else {
                await self.createNow(at: target)
            }
            self.migrationTask = nil
        }
    }

    private func snapshot() -> NoteSyncDocument {
        NoteSyncDocument(notes: store.notes, selectedID: store.selectedID)
    }

    private func startWatching() {
        guard watcher == nil, let fileURL, isRunning, isEnabled else { return }
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
