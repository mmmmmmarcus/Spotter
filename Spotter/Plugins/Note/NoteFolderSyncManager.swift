import Combine
import Foundation

/// Keeps every Note mirrored as one Markdown file in a folder the user picks — normally inside
/// iCloud Drive, which is what carries them between Macs. Choosing the folder is the consent act,
/// exactly as choosing a file is for Settings Sync.
@MainActor
final class NoteFolderSyncManager: ObservableObject {
    private enum Key {
        static let folderPath = "note.folder-sync.path"
    }

    /// Decode-only migration from the even older user-selected Notes JSON pipeline. It never grants
    /// folder sync and never deletes the user's file; it only makes sure those Notes reached the
    /// local archive before that path is forgotten.
    private struct LegacyKeys {
        let filePath: String
        let enabled: String
        let migrated: String

        init(bundleID: String) {
            filePath = bundleID + ".note-sync.file-path"
            enabled = bundleID + ".note-sync.enabled"
            migrated = bundleID + ".note-cloud-sync.legacy-json-migrated-v1"
        }
    }

    @Published private(set) var folderURL: URL?
    @Published private(set) var isWorking = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?
    /// Files present but not yet downloaded. They are never treated as deletions, only as pending.
    @Published private(set) var pendingDownloads = 0

    private let store: NoteStore
    private let defaults: UserDefaults
    private let legacyKeys: LegacyKeys
    private let io = NoteFolderIO()
    private let legacyIO = CoordinatedFileIO()
    private var watcher: CoordinatedFileWatcher?
    private var syncTask: Task<Void, Never>?
    private var downloadRetryTask: Task<Void, Never>?
    private var isRunning = false
    private var isSyncing = false
    private var isApplyingRemote = false
    private var needsAnotherPass = false

    init(
        store: NoteStore, defaults: UserDefaults = .standard,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.spotter.app1"
    ) {
        self.store = store
        self.defaults = defaults
        legacyKeys = LegacyKeys(bundleID: bundleID)
        folderURL = defaults.string(forKey: Key.folderPath).map(URL.init(fileURLWithPath:))
    }

    var isEnabled: Bool { folderURL != nil }

    var isICloudLocation: Bool {
        folderURL.map { FileManager.default.isUbiquitousItem(at: $0) } ?? false
    }

    var statusText: String {
        if let errorMessage { return errorMessage }
        guard folderURL != nil else { return "Off · Notes stay on this Mac" }
        if isWorking { return "Syncing…" }
        if pendingDownloads > 0 {
            return "Waiting for \(pendingDownloads) file\(pendingDownloads == 1 ? "" : "s") to download…"
        }
        guard let lastSyncedAt else { return "Waiting for the folder…" }
        return "Up to date · " + lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        store.onSyncSnapshotChanged = { [weak self] _ in self?.scheduleSync() }
        Task { [weak self] in
            await self?.migrateLegacyJSONIfNeeded()
            self?.startWatching()
            self?.scheduleSync()
        }
    }

    func stop() {
        isRunning = false
        store.onSyncSnapshotChanged = nil
        syncTask?.cancel()
        syncTask = nil
        downloadRetryTask?.cancel()
        downloadRetryTask = nil
        stopWatching()
    }

    func connect(to url: URL) {
        let folder = url.standardizedFileURL
        folderURL = folder
        defaults.set(folder.path, forKey: Key.folderPath)
        errorMessage = nil
        lastSyncedAt = nil
        stopWatching()
        startWatching()
        scheduleSync(immediately: true)
    }

    /// Disconnecting leaves every local Note and every file in the folder exactly where it is.
    func disconnect() {
        stopWatching()
        syncTask?.cancel()
        syncTask = nil
        downloadRetryTask?.cancel()
        downloadRetryTask = nil
        folderURL = nil
        lastSyncedAt = nil
        errorMessage = nil
        pendingDownloads = 0
        defaults.removeObject(forKey: Key.folderPath)
    }

    func syncNow() async {
        scheduleSync(immediately: true)
        await syncTask?.value
    }

    private func scheduleSync(immediately: Bool = false) {
        guard isRunning, folderURL != nil, !isApplyingRemote else { return }
        if isSyncing {
            needsAnotherPass = true
            return
        }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            if !immediately {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            await self?.runSyncPass()
        }
    }

    private func runSyncPass() async {
        guard isRunning, let folder = folderURL, !isSyncing else { return }
        isSyncing = true
        isWorking = true
        do {
            let local = store.syncSnapshot
            let scan = try await io.scan(folder: folder)
            let plan = NoteFolderReconciler.plan(local: local, scan: scan)
            if plan.snapshot != local {
                isApplyingRemote = true
                // Re-merges against whatever the store holds now, so a keystroke that landed during
                // the read still wins over the folder's older copy.
                store.applyRemoteSnapshot(plan.snapshot)
                isApplyingRemote = false
            }
            if plan.hasFileWork { try await io.apply(plan, in: folder) }
            if !plan.adopted.isEmpty || !plan.forked.isEmpty {
                AppLog.info(
                    "note-folder-sync",
                    "Adopted \(plan.adopted.count) file(s) and forked \(plan.forked.count) duplicate(s).")
            }
            pendingDownloads = plan.deferred.count
            errorMessage = nil
            lastSyncedAt = Date()
            scheduleDownloadRetryIfNeeded()
        } catch {
            isApplyingRemote = false
            errorMessage = "Couldn’t sync the Notes folder: " + error.localizedDescription
            AppLog.error("note-folder-sync", errorMessage ?? error.localizedDescription)
        }
        // Cleared here rather than in a `defer`, which would still be pending when the follow-up
        // pass below asks whether one is running — and the change that asked for it would be lost.
        isSyncing = false
        isWorking = false
        if needsAnotherPass {
            needsAnotherPass = false
            scheduleSync()
        }
    }

    /// A placeholder becomes a real file without any coordinated change Spotter can observe, so the
    /// only way to notice the download finishing is to look again while something is still pending.
    private func scheduleDownloadRetryIfNeeded() {
        downloadRetryTask?.cancel()
        guard pendingDownloads > 0 else {
            downloadRetryTask = nil
            return
        }
        downloadRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self, self.isRunning, self.folderURL != nil else { return }
            self.downloadRetryTask = nil
            self.scheduleSync(immediately: true)
        }
    }

    private func startWatching() {
        guard watcher == nil, isRunning, let folderURL else { return }
        watcher = CoordinatedFileWatcher(url: folderURL, isDirectory: true) { [weak self] in
            self?.scheduleSync()
        }
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func migrateLegacyJSONIfNeeded() async {
        guard !defaults.bool(forKey: legacyKeys.migrated) else { return }
        guard defaults.bool(forKey: legacyKeys.enabled),
            let path = defaults.string(forKey: legacyKeys.filePath)
        else {
            finishLegacyMigration()
            return
        }
        do {
            let data = try await legacyIO.read(from: URL(fileURLWithPath: path))
            let document = try await NoteSyncDocument.decodedOffMain(data)
            guard isRunning else { return }
            store.applyRemoteSnapshot(
                NoteSyncSnapshot(notes: document.notes, tombstones: []))
            finishLegacyMigration()
        } catch {
            guard isRunning else { return }
            AppLog.error(
                "note-folder-sync",
                "Couldn’t import the former Notes sync file: " + error.localizedDescription)
        }
    }

    private func finishLegacyMigration() {
        defaults.set(true, forKey: legacyKeys.migrated)
        defaults.removeObject(forKey: legacyKeys.filePath)
        defaults.removeObject(forKey: legacyKeys.enabled)
    }
}
