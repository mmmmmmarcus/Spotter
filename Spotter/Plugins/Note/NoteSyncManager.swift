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
            let containers = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
                as? [String],
            let services = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
            let push = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.aps-environment" as CFString, nil) as? String,
            !push.isEmpty,
            containerEnvironment != nil
        else { return false }
        return containers.contains(NoteCloudSyncEngine.containerIdentifier)
            && services.contains("CloudKit")
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
    private var retryTask: Task<Void, Never>?
    private var migrationTask: Task<Void, Never>?
    private var isRunning = false
    private var retryAttempt = 0

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
        guard isRunning, isEnabled, cloudKitAvailable else { return false }
        if cloud == nil {
            retryTask?.cancel()
            retryTask = nil
            startCloud()
        }
        if let startTask { await startTask.value }
        guard isRunning, isEnabled, let cloud, self.cloud === cloud else {
            // startCloud records why it could not come up; only fill in when it stayed silent.
            if errorMessage == nil {
                errorMessage = "iCloud sync hasn’t started yet. Try again shortly."
            }
            AppLog.error("note-cloud-sync", "Sync Now found no live engine: \(statusText)")
            return false
        }
        isWorking = true
        errorMessage = nil
        do {
            let settled = try await cloud.syncNow()
            guard isRunning, isEnabled, self.cloud === cloud else { return false }
            isWorking = false
            if !settled, errorMessage == nil {
                errorMessage = "iCloud still has pending Note changes. Try again shortly."
                AppLog.error(
                    "note-cloud-sync", "Sync Now finished with Note changes still pending.")
            }
            return settled
        } catch {
            guard isRunning, isEnabled, self.cloud === cloud else { return false }
            isWorking = false
            errorMessage = NoteCloudSyncError.message(for: error)
            AppLog.error(
                "note-cloud-sync", NoteCloudSyncError.diagnosticDescription(for: error))
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
                self.isWorking = false
                self.startTask = nil
            } catch {
                guard let self, self.isRunning, self.isEnabled, self.cloud === cloud else { return }
                self.isWorking = false
                self.errorMessage = NoteCloudSyncError.message(for: error)
                self.startTask = nil
                AppLog.error(
                    "note-cloud-sync", NoteCloudSyncError.diagnosticDescription(for: error))
                let shouldRetry = NoteCloudSyncError.isRetryable(error)
                self.cloud = nil
                await cloud.stop(deleteState: false)
                guard self.isRunning, self.isEnabled else { return }
                if shouldRetry { self.scheduleCloudRetry() }
            }
        }
    }

    private func stopCloud(deleteState: Bool) {
        startTask?.cancel()
        pushTask?.cancel()
        retryTask?.cancel()
        startTask = nil
        pushTask = nil
        retryTask = nil
        retryAttempt = 0
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
            if let startTask = self?.startTask { await startTask.value }
            guard let self, self.isRunning, self.isEnabled, self.cloud === cloud else { return }
            await cloud.applyLocalSnapshot(snapshot)
            guard self.isRunning, self.isEnabled, self.cloud === cloud else { return }
            do {
                _ = try await cloud.sendPendingChanges()
                guard self.isRunning, self.isEnabled, self.cloud === cloud else { return }
            } catch {
                guard self.isRunning, self.isEnabled, self.cloud === cloud else { return }
                self.errorMessage = NoteCloudSyncError.message(for: error)
                AppLog.error(
                    "note-cloud-sync", NoteCloudSyncError.diagnosticDescription(for: error))
            }
        }
    }

    private func scheduleCloudRetry() {
        retryTask?.cancel()
        let delays = [5, 15, 30, 60, 120]
        let delay = delays[min(retryAttempt, delays.count - 1)]
        retryAttempt += 1
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, self.isRunning, self.isEnabled, self.cloud == nil else { return }
            self.retryTask = nil
            self.startCloud()
        }
    }

    private func handle(_ event: NoteCloudSyncEvent) {
        guard isRunning, isEnabled else { return }
        switch event {
        case .received(let snapshot):
            store.applyCloudSnapshot(snapshot)
        case .didSync:
            errorMessage = nil
            let isFirstSync = lastSyncedAt == nil
            lastSyncedAt = Date()
            retryAttempt = 0
            if isFirstSync {
                AppLog.info(
                    "note-cloud-sync",
                    "\(NoteCloudCapability.containerEnvironment ?? "unknown") CloudKit sync is up to date.")
            }
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
