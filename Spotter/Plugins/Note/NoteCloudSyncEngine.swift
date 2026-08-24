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

    static func message(for error: Error) -> String {
        guard let cloud = cloudError(in: error) else {
            if error is CancellationError { return "Sync was cancelled." }
            return error.localizedDescription + " See Settings → Diagnostics."
        }
        switch cloud.code {
        case .networkUnavailable:
            return "No network connection. Notes will retry when this Mac is online."
        case .networkFailure, .serverResponseLost:
            return "The network is available, but iCloud couldn’t be reached. Try again shortly."
        case .serviceUnavailable, .zoneBusy, .accountTemporarilyUnavailable:
            return "iCloud is temporarily unavailable. Notes will retry automatically."
        case .requestRateLimited:
            return "iCloud is receiving too many requests. Notes will retry automatically."
        case .notAuthenticated:
            return "Sign in to iCloud in System Settings to synchronize Notes."
        case .missingEntitlement, .badContainer, .permissionFailure:
            return "This Spotter build isn’t authorized for Notes iCloud Sync."
        case .managedAccountRestricted:
            return "This managed iCloud account isn’t allowed to use CloudKit."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free some space to synchronize Notes."
        case .invalidArguments, .constraintViolation:
            return "iCloud rejected Spotter’s Note record. The SpotterNote schema may be missing "
                + "from this container. See Settings → Diagnostics."
        case .limitExceeded:
            return "This Note is too large for one iCloud request."
        case .zoneNotFound, .userDeletedZone:
            return "The Notes zone is missing from iCloud. Spotter recreates it on the next "
                + "sync."
        case .internalError, .serverRejectedRequest:
            return "iCloud rejected the request (CloudKit error \(cloud.errorCode)). "
                + "See Settings → Diagnostics."
        default:
            return cloud.localizedDescription + " (CloudKit error \(cloud.errorCode))"
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        guard let code = cloudError(in: error)?.code else { return false }
        switch code {
        case .networkUnavailable, .networkFailure, .serverResponseLost, .serviceUnavailable,
            .zoneBusy, .accountTemporarilyUnavailable, .requestRateLimited:
            return true
        default:
            return false
        }
    }

    static func diagnosticDescription(for error: Error) -> String {
        var descriptions: [String] = []
        appendDiagnostic(error, to: &descriptions, depth: 0)
        var text = descriptions.joined(separator: " <- ")
        // CloudKit throws Swift errors whose payload the NSError bridge flattens away; the
        // reflected form is the only place the real case and its associated values survive.
        let reflected = String(reflecting: error).prefix(400)
        if !reflected.isEmpty { text += " | " + reflected }
        return text
    }

    private static func appendDiagnostic(
        _ error: Error, to descriptions: inout [String], depth: Int
    ) {
        guard depth < 4, descriptions.count < 8 else { return }
        let cocoa = error as NSError
        descriptions.append("\(cocoa.domain) \(cocoa.code): \(cocoa.localizedDescription)")
        if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? Error {
            appendDiagnostic(underlying, to: &descriptions, depth: depth + 1)
        }
        if let partial = cocoa.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for nested in partial.values.prefix(3) where descriptions.count < 8 {
                appendDiagnostic(nested, to: &descriptions, depth: depth + 1)
            }
        }
    }

    private static func cloudError(in error: Error) -> CKError? {
        if let cloud = error as? CKError {
            guard cloud.code == .partialFailure else { return cloud }
            // "Failed to modify some records" describes nothing; the per-item error is the reason.
            for nested in (cloud.partialErrorsByItemID ?? [:]).values {
                if let inner = nested as? CKError, inner.code != .partialFailure { return inner }
            }
            return cloud
        }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
            let cloud = cloudError(in: underlying)
        {
            return cloud
        }
        if let partial = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            for nested in partial.values {
                if let cloud = cloudError(in: nested) { return cloud }
            }
        }
        return nil
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
    // CKDatabase holds no strong reference to its container; without this the engine's database
    // loses its container after `start()` returns and every later fetch/send fails.
    private var container: CKContainer?
    private var syncEngine: CKSyncEngine?
    private var shouldPersistState = true
    private var initialChangesQueued = false

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
        AppLog.info(
            "note-cloud-sync",
            "Starting \(NoteCloudCapability.containerEnvironment ?? "unknown") CloudKit sync in "
                + Self.containerIdentifier)
        let container = CKContainer(identifier: Self.containerIdentifier)
        self.container = container
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

        log(
            "Engine ready with \(items.count) local item(s), "
                + "\(engineState == nil ? "fresh" : "restored") state.")
        try await engine.fetchChanges()
        guard await hasConsent(), syncEngine != nil else { return }
        queueInitialChangesIfNeeded(on: engine)
        try await engine.sendChanges()
        guard await hasConsent(), syncEngine != nil else { return }
        let settled = await reportSyncIfSettled()
        log("Initial sync \(settled ? "settled" : "unsettled") — \(pendingSummary(engine)).")
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

    func sendPendingChanges() async throws -> Bool {
        guard await hasConsent(), let syncEngine else { return false }
        queueInitialChangesIfNeeded(on: syncEngine)
        try await syncEngine.sendChanges()
        guard await hasConsent(), self.syncEngine != nil else { return false }
        return await reportSyncIfSettled()
    }

    func syncNow() async throws -> Bool {
        guard await hasConsent(), let syncEngine else {
            AppLog.error("note-cloud-sync", "Manual sync ran with no live engine.")
            return false
        }
        log("Manual sync: fetching — \(pendingSummary(syncEngine)).")
        try await syncEngine.fetchChanges()
        guard await hasConsent(), self.syncEngine != nil else { return false }
        queueInitialChangesIfNeeded(on: syncEngine)
        log("Manual sync: sending — \(pendingSummary(syncEngine)).")
        try await syncEngine.sendChanges()
        guard await hasConsent(), self.syncEngine != nil else { return false }
        let settled = await reportSyncIfSettled()
        log("Manual sync \(settled ? "settled" : "unsettled") — \(pendingSummary(syncEngine)).")
        return settled
    }

    func stop(deleteState: Bool) async {
        if deleteState { shouldPersistState = false }
        let engine = syncEngine
        syncEngine = nil
        if let engine { await engine.cancelOperations() }
        container = nil
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
                AppLog.error(
                    "note-cloud-sync",
                    "Notes zone save failed with CloudKit code \(failure.error.errorCode).")
                await report(failure.error)
            }
        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)
        case .didFetchChanges:
            guard await hasConsent() else { return }
            queueInitialChangesIfNeeded(on: syncEngine)
            _ = await reportSyncIfSettled()
        case .didSendChanges:
            _ = await reportSyncIfSettled()
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
        let scoped = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        let itemSnapshot = items
        let systemFieldsSnapshot = recordSystemFields
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        var unresolved: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in scoped {
            guard case .saveRecord(let recordID) = change else {
                pending.append(change)
                continue
            }
            if UUID(uuidString: recordID.recordName).flatMap({ itemSnapshot[$0] }) == nil {
                unresolved.append(change)
            } else {
                pending.append(change)
            }
        }
        if !unresolved.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: unresolved)
            AppLog.error(
                "note-cloud-sync",
                "Dropped \(unresolved.count) pending save(s) with no matching local Note.")
        }
        guard !pending.isEmpty else { return nil }
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
        if !event.failedRecordSaves.isEmpty {
            let codes = Set(event.failedRecordSaves.map(\.error.errorCode)).sorted()
                .map(String.init).joined(separator: ", ")
            AppLog.error(
                "note-cloud-sync",
                "Sent \(event.savedRecords.count) record(s); "
                    + "\(event.failedRecordSaves.count) failed with CloudKit code(s) \(codes).")
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
                .notAuthenticated:
                await report(failure.error)
            case .operationCancelled:
                break
            default:
                await report(failure.error)
            }
        }
        if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }
        persistState()
        guard !accepted.isEmpty, await hasConsent() else { return }
        await onEvent(.received(NoteSyncMerge.snapshot(from: accepted)))
    }

    private func queueInitialChangesIfNeeded(on syncEngine: CKSyncEngine) {
        guard !initialChangesQueued else { return }
        initialChangesQueued = true
        syncEngine.state.add(
            pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        syncEngine.state.add(
            pendingRecordZoneChanges: items.keys.map { .saveRecord(recordID(for: $0)) })
    }

    private func reportSyncIfSettled() async -> Bool {
        guard initialChangesQueued, await hasConsent(), let syncEngine else { return false }
        guard syncEngine.state.pendingDatabaseChanges.isEmpty,
            syncEngine.state.pendingRecordZoneChanges.isEmpty
        else { return false }
        await onEvent(.didSync)
        return true
    }

    private func log(_ message: String) {
        AppLog.info("note-cloud-sync", message)
    }

    private func pendingSummary(_ engine: CKSyncEngine) -> String {
        "\(engine.state.pendingDatabaseChanges.count) zone change(s), "
            + "\(engine.state.pendingRecordZoneChanges.count) record change(s) pending"
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

    private func report(_ error: Error) async {
        let message = NoteCloudSyncError.message(for: error)
        AppLog.error("note-cloud-sync", NoteCloudSyncError.diagnosticDescription(for: error))
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
            record.encryptedValues["contentUpdatedAt"] = note.contentUpdatedAt
            record.encryptedValues["tint"] = note.tint?.rawValue
            record.encryptedValues["deletedAt"] = nil
        case .tombstone(let tombstone):
            record.encryptedValues["content"] = nil
            record.encryptedValues["createdAt"] = nil
            record.encryptedValues["updatedAt"] = tombstone.deletedAt
            record.encryptedValues["contentUpdatedAt"] = nil
            record.encryptedValues["tint"] = nil
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
        // Both fields are additive: a record written before tints decodes as an untinted Note
        // whose order falls back to its edit time.
        let contentUpdatedAt = record.encryptedValues["contentUpdatedAt"] as? Date
        let tint = (record.encryptedValues["tint"] as? String).flatMap(NoteTint.init(rawValue:))
        return .note(
            SpotterNote(
                id: id, content: content, createdAt: createdAt, updatedAt: updatedAt,
                contentUpdatedAt: contentUpdatedAt, tint: tint))
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
