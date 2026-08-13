import Combine
import Foundation
import Security

enum NoteCloudCapability {
    static var containerEnvironment: String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(
            task, "com.apple.developer.icloud-container-environment" as CFString, nil)
            as? String
    }

    static var stateFileName: String {
        guard let containerEnvironment else { return "cloud-sync-state.json" }
        return "cloud-sync-" + containerEnvironment.lowercased() + "-state.json"
    }

    static var isAvailable: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
                as? [String]
        else { return false }
        return value.contains(NoteCloudSyncEngine.containerIdentifier)
    }
}

@MainActor
final class NoteSyncManager: ObservableObject {
    private struct Keys {
        let enabled: String
        let legacyFilePath: String
        let legacyEnabled: String
        let migrated: String

        init(bundleID: String) {
            enabled = bundleID + ".note-cloud-sync.enabled"
            legacyFilePath = bundleID + ".note-sync.file-path"
            legacyEnabled = bundleID + ".note-sync.enabled"
            migrated = bundleID + ".note-cloud-sync.legacy-json-migrated-v1"
        }
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?

    private let store: NoteStore
    private let defaults: UserDefaults
    private let keys: Keys
    private let stateURL: URL
    private let legacyIO = CoordinatedFileIO()
    private var cloud: NoteCloudSyncEngine?
    private var startTask: Task<Void, Never>?
    private var pushTask: Task<Void, Never>?
    private var migrationTask: Task<Void, Never>?
    private var isRunning = false

    init(
        store: NoteStore, defaults: UserDefaults = .standard,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.spotter.app1",
        stateURL: URL? = nil
    ) {
        self.store = store
        self.defaults = defaults
        keys = Keys(bundleID: bundleID)
        isEnabled = defaults.bool(forKey: keys.enabled)
        self.stateURL = stateURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Notes", isDirectory: true)
            .appendingPathComponent(NoteCloudCapability.stateFileName)
    }

    var statusText: String {
        if let errorMessage { return errorMessage }
        if isWorking { return "Syncing with iCloud…" }
        guard isEnabled else { return "Off · Notes stay on this Mac" }
        guard let lastSyncedAt else { return "Waiting for iCloud…" }
        return "Up to date · " + lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }

    var cloudKitAvailable: Bool { NoteCloudCapability.isAvailable }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        store.onSyncSnapshotChanged = { [weak self] snapshot in
            self?.schedulePush(snapshot)
        }
        migrationTask?.cancel()
        migrationTask = Task { [weak self] in
            guard let self else { return }
            await self.migrateLegacyJSONIfNeeded()
            guard !Task.isCancelled, self.isRunning, self.isEnabled else { return }
            self.startCloud()
        }
    }

    func stop() {
        isRunning = false
        store.onSyncSnapshotChanged = nil
        migrationTask?.cancel()
        migrationTask = nil
        stopCloud(deleteState: false)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: keys.enabled)
        errorMessage = nil
        if enabled {
            if isRunning { startCloud() }
        } else {
            lastSyncedAt = nil
            stopCloud(deleteState: true)
        }
    }

    func syncNow() async -> Bool {
        guard isRunning, isEnabled else { return false }
        guard let cloud else {
            startCloud()
            return false
        }
        isWorking = true
        errorMessage = nil
        do {
            try await cloud.syncNow()
            guard isRunning, isEnabled, self.cloud === cloud else { return false }
            lastSyncedAt = Date()
            isWorking = false
            return true
        } catch {
            guard isRunning, isEnabled, self.cloud === cloud else { return false }
            isWorking = false
            errorMessage = error.localizedDescription
            AppLog.error("note-cloud-sync", error.localizedDescription)
            return false
        }
    }

    private func startCloud() {
        guard isRunning, isEnabled, cloud == nil, startTask == nil else { return }
        guard cloudKitAvailable else {
            errorMessage = "CloudKit isn’t available in this build."
            return
        }
        isWorking = true
        errorMessage = nil
        let cloud = NoteCloudSyncEngine(
            snapshot: store.syncSnapshot, stateURL: stateURL,
            hasConsent: { [weak self] in
                self?.isRunning == true && self?.isEnabled == true
            },
            onEvent: { [weak self] event in self?.handle(event) })
        self.cloud = cloud
        startTask = Task { [weak self, cloud] in
            do {
                try await cloud.start()
                guard let self, self.isRunning, self.isEnabled, self.cloud === cloud else { return }
                self.lastSyncedAt = Date()
                self.isWorking = false
                self.startTask = nil
            } catch {
                guard let self, self.isRunning, self.isEnabled, self.cloud === cloud else { return }
                self.isWorking = false
                self.errorMessage = error.localizedDescription
                self.startTask = nil
                self.cloud = nil
                AppLog.error("note-cloud-sync", error.localizedDescription)
                await cloud.stop(deleteState: false)
            }
        }
    }

    private func stopCloud(deleteState: Bool) {
        startTask?.cancel()
        pushTask?.cancel()
        startTask = nil
        pushTask = nil
        isWorking = false
        let cloud = cloud
        self.cloud = nil
        Task { await cloud?.stop(deleteState: deleteState) }
        if deleteState, cloud == nil { try? FileManager.default.removeItem(at: stateURL) }
    }

    private func schedulePush(_ snapshot: NoteSyncSnapshot) {
        guard isRunning, isEnabled, let cloud else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self, cloud] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard let self, self.isRunning, self.isEnabled, self.cloud === cloud else { return }
            await cloud.applyLocalSnapshot(snapshot)
            guard self.isRunning, self.isEnabled, self.cloud === cloud else { return }
            do {
                try await cloud.sendPendingChanges()
                guard self.isRunning, self.isEnabled, self.cloud === cloud else { return }
                self.lastSyncedAt = Date()
            } catch {
                guard self.isRunning, self.isEnabled, self.cloud === cloud else { return }
                self.errorMessage = error.localizedDescription
                AppLog.error("note-cloud-sync", error.localizedDescription)
            }
        }
    }

    private func handle(_ event: NoteCloudSyncEvent) {
        guard isRunning, isEnabled else { return }
        switch event {
        case .received(let snapshot):
            store.applyCloudSnapshot(snapshot)
        case .didSync:
            errorMessage = nil
            lastSyncedAt = Date()
        case .error(let message):
            errorMessage = message
        case .accountChanged:
            setEnabled(false)
            errorMessage = "iCloud account changed. Turn sync on again for the current account."
        }
    }

    private func migrateLegacyJSONIfNeeded() async {
        guard !defaults.bool(forKey: keys.migrated) else { return }
        guard defaults.bool(forKey: keys.legacyEnabled),
            let path = defaults.string(forKey: keys.legacyFilePath)
        else {
            finishLegacyMigration()
            return
        }
        do {
            let data = try await legacyIO.read(from: URL(fileURLWithPath: path))
            let document = try await NoteSyncDocument.decodedOffMain(data)
            guard isRunning else { return }
            store.replace(notes: document.notes, selectedID: document.selectedID)
            finishLegacyMigration()
        } catch {
            guard isRunning else { return }
            errorMessage = "Couldn’t import the former Notes sync file: " + error.localizedDescription
            AppLog.error("note-cloud-sync", errorMessage ?? error.localizedDescription)
        }
    }

    private func finishLegacyMigration() {
        defaults.set(true, forKey: keys.migrated)
        defaults.removeObject(forKey: keys.legacyFilePath)
        defaults.removeObject(forKey: keys.legacyEnabled)
    }
}
