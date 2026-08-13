import CloudKit
import Foundation

enum NoteCloudSyncEvent: Sendable {
    case received(NoteSyncSnapshot)
    case didSync
    case error(String)
    case accountChanged
}

enum NoteCloudSyncError: LocalizedError {
    case noAccount
    case restricted
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud to synchronize Notes."
        case .restricted: "iCloud access is restricted on this Mac."
        case .unavailable: "Couldn’t determine the current iCloud account."
        }
    }
}

private struct NoteCloudStateArchive: Codable, Sendable {
    static let supportedVersion = 1

    var version = supportedVersion
    var engineState: CKSyncEngine.State.Serialization?
    var recordSystemFields: [String: Data] = [:]
}

actor NoteCloudSyncEngine: CKSyncEngineDelegate {
    static let containerIdentifier = "iCloud.com.spotter.app"
    private static let zoneName = "SpotterNotes"
    private static let recordType = "SpotterNote"

    private let stateURL: URL
    private let hasConsent: @MainActor @Sendable () -> Bool
    private let onEvent: @MainActor @Sendable (NoteCloudSyncEvent) -> Void
    private var items: [UUID: NoteSyncItem]
    private var recordSystemFields: [UUID: Data] = [:]
    private var engineState: CKSyncEngine.State.Serialization?
    private var syncEngine: CKSyncEngine?
    private var shouldPersistState = true

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: Self.zoneName) }

    init(
        snapshot: NoteSyncSnapshot, stateURL: URL,
        hasConsent: @escaping @MainActor @Sendable () -> Bool,
        onEvent: @escaping @MainActor @Sendable (NoteCloudSyncEvent) -> Void
    ) {
        items = NoteSyncMerge.items(in: snapshot)
        self.stateURL = stateURL
        self.hasConsent = hasConsent
        self.onEvent = onEvent
    }

    func start() async throws {
        guard await hasConsent() else { return }
        shouldPersistState = true
        let container = CKContainer(identifier: Self.containerIdentifier)
        let accountStatus = try await container.accountStatus()
        guard await hasConsent() else { return }
        switch accountStatus {
        case .available: break
        case .noAccount: throw NoteCloudSyncError.noAccount
        case .restricted: throw NoteCloudSyncError.restricted
        case .couldNotDetermine, .temporarilyUnavailable: throw NoteCloudSyncError.unavailable
        @unknown default: throw NoteCloudSyncError.unavailable
        }

        loadState()
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: engineState,
            delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        syncEngine = engine

        try await engine.fetchChanges()
        guard await hasConsent(), syncEngine != nil else { return }
        queueZoneAndAllItems(on: engine)
        try await engine.sendChanges()
        guard await hasConsent(), syncEngine != nil else { return }
        await onEvent(.didSync)
    }

    func applyLocalSnapshot(_ snapshot: NoteSyncSnapshot) async {
        guard await hasConsent(), let syncEngine else { return }
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for (id, candidate) in NoteSyncMerge.items(in: snapshot) {
            if let current = items[id] {
                let winner = NoteSyncMerge.preferred(current, candidate)
                guard winner == candidate, winner != current else { continue }
            }
            items[id] = candidate
            pending.append(.saveRecord(recordID(for: id)))
        }
        guard !pending.isEmpty else { return }
        syncEngine.state.add(pendingRecordZoneChanges: pending)
    }

    func sendPendingChanges() async throws {
        guard await hasConsent(), let syncEngine else { return }
        try await syncEngine.sendChanges()
        guard await hasConsent(), self.syncEngine != nil else { return }
        await onEvent(.didSync)
    }

    func syncNow() async throws {
        guard await hasConsent(), let syncEngine else { return }
        try await syncEngine.fetchChanges()
        guard await hasConsent(), self.syncEngine != nil else { return }
        try await syncEngine.sendChanges()
        guard await hasConsent(), self.syncEngine != nil else { return }
        await onEvent(.didSync)
    }

    func stop(deleteState: Bool) async {
        if deleteState { shouldPersistState = false }
        let engine = syncEngine
        syncEngine = nil
        if let engine { await engine.cancelOperations() }
        if deleteState { try? FileManager.default.removeItem(at: stateURL) }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            guard shouldPersistState else { return }
            engineState = event.stateSerialization
            persistState()
        case .accountChange(let event):
            switch event.changeType {
            case .signIn: break
            case .signOut, .switchAccounts:
                guard await hasConsent() else { return }
                await onEvent(.accountChanged)
            @unknown default: break
            }
        case .fetchedDatabaseChanges(let event):
            guard await hasConsent() else { return }
            if event.deletions.contains(where: { $0.zoneID == zoneID }) {
                syncEngine.state.add(
                    pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                syncEngine.state.add(
                    pendingRecordZoneChanges: items.keys.map { .saveRecord(recordID(for: $0)) })
            }
        case .fetchedRecordZoneChanges(let event):
            await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)
        case .sentDatabaseChanges(let event):
            for failure in event.failedZoneSaves where failure.zone.zoneID == zoneID {
                await report(failure.error.localizedDescription)
            }
        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)
        case .didFetchChanges, .didSendChanges:
            guard await hasConsent() else { return }
            await onEvent(.didSync)
        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
            .willSendChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard await hasConsent() else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        let itemSnapshot = items
        let systemFieldsSnapshot = recordSystemFields
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let id = UUID(uuidString: recordID.recordName),
                let item = itemSnapshot[id]
            else { return nil }
            return Self.makeRecord(
                for: item, recordID: recordID, systemFields: systemFieldsSnapshot[id])
        }
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges, syncEngine: CKSyncEngine
    ) async {
        guard await hasConsent() else { return }
        var accepted: [UUID: NoteSyncItem] = [:]
        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        for modification in event.modifications {
            let record = modification.record
            guard record.recordType == Self.recordType,
                let id = UUID(uuidString: record.recordID.recordName),
                let remote = Self.item(from: record)
            else { continue }
            recordSystemFields[id] = Self.encodeSystemFields(record)
            if let local = items[id] {
                let winner = NoteSyncMerge.preferred(local, remote)
                items[id] = winner
                if winner == remote, winner != local {
                    accepted[id] = winner
                } else if winner == local, winner != remote {
                    retry.append(.saveRecord(record.recordID))
                }
            } else {
                items[id] = remote
                accepted[id] = remote
            }
        }
        for deletion in event.deletions {
            guard let id = UUID(uuidString: deletion.recordID.recordName) else { continue }
            recordSystemFields.removeValue(forKey: id)
        }
        if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
        persistState()
        guard !accepted.isEmpty, await hasConsent() else { return }
        await onEvent(.received(NoteSyncMerge.snapshot(from: accepted)))
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine
    ) async {
        guard await hasConsent() else { return }
        for record in event.savedRecords {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            recordSystemFields[id] = Self.encodeSystemFields(record)
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var accepted: [UUID: NoteSyncItem] = [:]
        for failure in event.failedRecordSaves {
            let record = failure.record
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            switch failure.error.code {
            case .serverRecordChanged:
                guard let serverRecord = failure.error.serverRecord,
                    let remote = Self.item(from: serverRecord)
                else { continue }
                recordSystemFields[id] = Self.encodeSystemFields(serverRecord)
                if let local = items[id] {
                    let winner = NoteSyncMerge.preferred(local, remote)
                    items[id] = winner
                    if winner == local, winner != remote {
                        retry.append(.saveRecord(record.recordID))
                    } else if winner == remote, winner != local {
                        accepted[id] = winner
                    }
                } else {
                    items[id] = remote
                    accepted[id] = remote
                }
            case .zoneNotFound:
                recordSystemFields.removeValue(forKey: id)
                syncEngine.state.add(
                    pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                retry.append(.saveRecord(record.recordID))
            case .unknownItem:
                recordSystemFields.removeValue(forKey: id)
                retry.append(.saveRecord(record.recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                .notAuthenticated, .operationCancelled:
                break
            default:
                await report(failure.error.localizedDescription)
            }
        }
        if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
        persistState()
        guard !accepted.isEmpty, await hasConsent() else { return }
        await onEvent(.received(NoteSyncMerge.snapshot(from: accepted)))
    }

    private func queueZoneAndAllItems(on syncEngine: CKSyncEngine) {
        syncEngine.state.add(
            pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        syncEngine.state.add(
            pendingRecordZoneChanges: items.keys.map { .saveRecord(recordID(for: $0)) })
    }

    private func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString.lowercased(), zoneID: zoneID)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        guard let archive = try? decoder.decode(NoteCloudStateArchive.self, from: data),
            archive.version <= NoteCloudStateArchive.supportedVersion
        else { return }
        engineState = archive.engineState
        recordSystemFields = Dictionary(
            uniqueKeysWithValues: archive.recordSystemFields.compactMap { key, data in
                UUID(uuidString: key).map { ($0, data) }
            })
    }

    private func persistState() {
        let archive = NoteCloudStateArchive(
            engineState: engineState,
            recordSystemFields: Dictionary(
                uniqueKeysWithValues: recordSystemFields.map { ($0.key.uuidString.lowercased(), $0.value) }))
        do {
            let data = try JSONEncoder().encode(archive)
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            AppLog.error("note-cloud-sync", "Couldn’t persist CloudKit state: " + error.localizedDescription)
        }
    }

    private func report(_ message: String) async {
        AppLog.error("note-cloud-sync", message)
        guard await hasConsent() else { return }
        await onEvent(.error(message))
    }

    private static func makeRecord(
        for item: NoteSyncItem, recordID: CKRecord.ID, systemFields: Data?
    ) -> CKRecord {
        let record = systemFields.flatMap(decodeSystemFields)
            ?? CKRecord(recordType: recordType, recordID: recordID)
        switch item {
        case .note(let note):
            record.encryptedValues["content"] = note.content
            record.encryptedValues["createdAt"] = note.createdAt
            record.encryptedValues["updatedAt"] = note.updatedAt
            record.encryptedValues["deletedAt"] = nil
        case .tombstone(let tombstone):
            record.encryptedValues["content"] = nil
            record.encryptedValues["createdAt"] = nil
            record.encryptedValues["updatedAt"] = tombstone.deletedAt
            record.encryptedValues["deletedAt"] = tombstone.deletedAt
        }
        return record
    }

    private static func item(from record: CKRecord) -> NoteSyncItem? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        if let deletedAt = record.encryptedValues["deletedAt"] as? Date {
            return .tombstone(NoteTombstone(id: id, deletedAt: deletedAt))
        }
        guard let content = record.encryptedValues["content"] as? String,
            let createdAt = record.encryptedValues["createdAt"] as? Date,
            let updatedAt = record.encryptedValues["updatedAt"] as? Date
        else { return nil }
        return .note(
            SpotterNote(id: id, content: content, createdAt: createdAt, updatedAt: updatedAt))
    }

    private static func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }
}
