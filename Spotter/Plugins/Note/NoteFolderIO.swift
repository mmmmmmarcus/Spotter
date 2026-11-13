import Foundation

/// Reads and writes the Notes folder under `NSFileCoordinator`, the way `SettingsSyncManager` does
/// for its single file. Nothing here decides policy: `NoteFolderReconciler` does, and this actor
/// only performs the plan it produced.
actor NoteFolderIO {
    enum Failure: LocalizedError {
        case unreachable(String)
        case changedDuringSync

        var errorDescription: String? {
            switch self {
            case .unreachable(let path): "The Notes folder isn’t available (\(path))."
            case .changedDuringSync: "The Notes folder changed during sync. Retrying…"
            }
        }
    }

    /// Thrown by an injected `trash` when the volume has no Trash at all (not when one failed): the file stays untouched and the pass continues, since the ledger's tombstone is the deletion.
    struct TrashUnavailable: Error {}

    private let trash: @Sendable (URL) throws -> Void
    /// Deleted Notes' files this folder could not trash, by name, with the bytes they held.
    private var retained: [String: String] = [:]

    init(trash: @escaping @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }) {
        self.trash = trash
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
    ]

    func scan(folder: URL) throws -> NoteFolderScan {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw Failure.unreachable(folder.path) }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<NoteFolderScan, Error>?
        coordinator.coordinate(readingItemAt: folder, options: [], error: &coordinationError) {
            url in
            result = Result { try readContents(of: url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    /// Returns the names of deleted Notes' files left in place because the folder has no Trash.
    @discardableResult
    func apply(_ plan: NoteFolderPlan, in folder: URL) throws -> [String] {
        retained = retained.filter { name, contents in
            guard case .deleted = plan.removals[name] else { return false }
            return plan.observed.files.first { $0.name == name }?.contents == contents
        }
        let settled = Set(retained.keys)
        // Coordinating a deletion that removes nothing still notifies the folder's watcher, so a pass with no other work stops here or it would never reach a fixpoint.
        guard plan.ledger != nil || plan.placements.contains(where: { $0.needsMove || $0.needsWrite })
            || plan.removals.keys.contains(where: { !settled.contains($0) })
        else { return settled.sorted() }
        for name in try performApply(plan, in: folder, skipping: settled) {
            retained[name] = plan.observed.files.first { $0.name == name }?.contents
        }
        return retained.keys.sorted()
    }

    private nonisolated func performApply(
        _ plan: NoteFolderPlan, in folder: URL, skipping settled: Set<String>
    ) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw Failure.unreachable(folder.path) }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<[String], Error>?
        coordinator.prepare(forReadingItemsAt: [], options: [], writingItemsAt: [folder], options: [],
            error: &coordinationError) { finished in
            defer { finished() }
            result = Result {
                let current = try readContents(of: folder)
                let expected = plan.observed.files.sorted { $0.name < $1.name }
                guard current.files.sorted(by: { $0.name < $1.name }) == expected,
                    current.ledger == plan.observed.ledger
                else { throw Failure.changedDuringSync }
                return try applyCoordinated(
                    plan, in: folder, skipping: settled, coordinator: coordinator)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private nonisolated func applyCoordinated(
        _ plan: NoteFolderPlan, in folder: URL, skipping settled: Set<String>,
        coordinator: NSFileCoordinator
    ) throws -> [String] {
        var untrashable: [String] = []
        // Publish deletion intent before removing bytes, so an interrupted pass cannot resurrect them.
        if let tombstones = plan.ledger {
            let data = try NoteFolderLedger(tombstones: tombstones).encoded()
            let url = folder.appendingPathComponent(NoteFolderFormat.ledgerFileName)
            try coordinateWrite(url, options: [], coordinator: coordinator) { target in
                guard readLedger(at: target, downloaded: true) == plan.observed.ledger
                    || (plan.observed.ledger == .missing && !FileManager.default.fileExists(atPath: target.path))
                else { throw Failure.changedDuringSync }
                try data.write(to: target, options: .atomic)
            }
        }
        for name in plan.removals.keys.sorted() {
            let url = folder.appendingPathComponent(name)
            guard let original = plan.observed.files.first(where: { $0.name == name })?.contents else {
                throw Failure.changedDuringSync
            }
            switch plan.removals[name] {
            case .deleted:
                guard !settled.contains(name) else { continue }
                do {
                    try coordinateWrite(url, options: .forDeleting, coordinator: coordinator) { target in
                        try requireContents(original, at: target)
                        try trash(target)
                    }
                } catch is TrashUnavailable {
                    untrashable.append(name)
                }
            case .redundantDuplicate:
                guard let survivor = plan.observed.files.first(where: {
                    $0.name != name && plan.removals[$0.name] == nil
                        && $0.contents.map { $0.utf8.elementsEqual(original.utf8) } == true
                }) else { throw Failure.changedDuringSync }
                try removeDuplicate(url, keeping: folder.appendingPathComponent(survivor.name),
                    contents: original, coordinator: coordinator)
            case nil:
                break
            }
        }
        let moving = plan.placements.filter(\.needsMove)
        // An imported plain file must carry its ID before a crash can strand it under a new name.
        for placement in moving where placement.needsWrite {
            try write(placement.contents, replacing: placement.currentContents,
                at: folder.appendingPathComponent(placement.currentName!), coordinator: coordinator)
        }
        try moveFiles(moving, in: folder, coordinator: coordinator)
        for placement in plan.placements where placement.needsWrite && !placement.needsMove {
            try write(placement.contents, replacing: placement.currentContents,
                at: folder.appendingPathComponent(placement.desiredName), coordinator: coordinator)
        }
        return untrashable
    }

    private nonisolated func moveFiles(_ placements: [NoteFolderPlacement], in folder: URL, coordinator: NSFileCoordinator) throws {
        var pending = placements.map { (source: $0.currentName!, target: $0.desiredName, id: $0.id, contents: $0.contents) }
        while !pending.isEmpty {
            if let index = pending.firstIndex(where: {
                !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.target).path)
            }) {
                let item = pending.remove(at: index)
                try move(folder.appendingPathComponent(item.source), to: folder.appendingPathComponent(item.target),
                    contents: item.contents, coordinator: coordinator)
            } else {
                // Only a legacy filename cycle needs staging; ordinary migration is a single move.
                let item = pending[0]
                let temporary = NoteFolderFormat.temporaryName(for: item.id)
                guard item.source != temporary,
                    pending.contains(where: { $0.source.lowercased() == item.target.lowercased() })
                else { throw Failure.changedDuringSync }
                try move(folder.appendingPathComponent(item.source), to: folder.appendingPathComponent(temporary),
                    contents: item.contents, coordinator: coordinator)
                pending[0].source = temporary
            }
        }
    }

    private nonisolated func coordinateWrite(_ url: URL, options: NSFileCoordinator.WritingOptions,
        coordinator: NSFileCoordinator, action: (URL) throws -> Void) throws {
        var error: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: options, error: &error) { target in
            result = Result { try action(target) }
        }
        if let error { throw error }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private nonisolated func requireContents(_ expected: String?, at url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if let expected {
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                try Data(contentsOf: url) == Data(expected.utf8)
            else { throw Failure.changedDuringSync }
        } else if values != nil || FileManager.default.fileExists(atPath: url.path) {
            throw Failure.changedDuringSync
        }
    }

    private nonisolated func write(_ contents: String, replacing expected: String?, at url: URL,
        coordinator: NSFileCoordinator) throws {
        try coordinateWrite(url, options: .forMerging, coordinator: coordinator) { target in
            try requireContents(expected, at: target)
            try Data(contents.utf8).write(to: target, options: .atomic)
        }
    }

    private nonisolated func move(_ source: URL, to destination: URL, contents: String,
        coordinator: NSFileCoordinator) throws {
        var error: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing, error: &error) { from, to in
            result = Result {
                try requireContents(contents, at: from)
                try requireContents(nil, at: to)
                coordinator.item(at: from, willMoveTo: to)
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            }
        }
        if let error { throw error }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private nonisolated func removeDuplicate(_ duplicate: URL, keeping survivor: URL, contents: String,
        coordinator: NSFileCoordinator) throws {
        var error: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(readingItemAt: survivor, options: [],
            writingItemAt: duplicate, options: .forDeleting, error: &error) { kept, removed in
            result = Result {
                // Both files are claimed together: cleanup cannot race a surviving copy's edit.
                try requireContents(contents, at: kept)
                try requireContents(contents, at: removed)
                try FileManager.default.removeItem(at: removed)
            }
        }
        if let error { throw error }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private nonisolated func readContents(of folder: URL) throws -> NoteFolderScan {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsSubdirectoryDescendants])
        var files: [NoteFolderFile] = []
        var ledger: NoteFolderLedgerState = .missing
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(Self.resourceKeys))
            let name = entry.lastPathComponent
            let downloaded = isDownloaded(values)
            if let placeholder = placeholderTarget(of: name) {
                // An undownloaded item can also appear under a `.name.icloud` alias. Reserving the
                // real name is what stops Spotter writing a second file over the top of it.
                if placeholder == NoteFolderFormat.ledgerFileName {
                    ledger = .unavailable
                } else if NoteFolderFormat.isNoteFileName(placeholder) {
                    files.append(NoteFolderFile(name: placeholder, contents: nil))
                }
                continue
            }
            if name == NoteFolderFormat.ledgerFileName {
                ledger = values?.isRegularFile == true && values?.isSymbolicLink != true
                    ? readLedger(at: entry, downloaded: downloaded) : .unavailable
                continue
            }
            guard NoteFolderFormat.isNoteFileName(name) else { continue }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                downloaded, let data = try? Data(contentsOf: entry),
                let text = String(data: data, encoding: .utf8)
            else {
                if !downloaded { try? FileManager.default.startDownloadingUbiquitousItem(at: entry) }
                files.append(NoteFolderFile(name: name, contents: nil))
                continue
            }
            files.append(
                NoteFolderFile(
                    name: name, contents: text, modifiedAt: values?.contentModificationDate))
        }
        return NoteFolderScan(files: files, ledger: ledger)
    }

    private nonisolated func readLedger(at url: URL, downloaded: Bool) -> NoteFolderLedgerState {
        guard downloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return .unavailable
        }
        guard let data = try? Data(contentsOf: url),
            let decoded = try? NoteFolderLedger(json: data)
        else { return .unavailable }
        return .readable(decoded.tombstones)
    }

    private nonisolated func isDownloaded(_ values: URLResourceValues?) -> Bool {
        guard values?.isUbiquitousItem == true else { return true }
        guard let status = values?.ubiquitousItemDownloadingStatus else { return true }
        return status == .current
    }

    /// `.Groceries.md.icloud` names the not-yet-downloaded `Groceries.md`.
    private nonisolated func placeholderTarget(of name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}

/// Remembers that a folder has been adopted but not yet reconciled — a decision `NoteFolderPass`
/// defines and this only stores, on the same Foundation-not-pure tier as the IO beside it so the
/// harness can drive its whole lifecycle. It is per-Mac and deliberately outlives a relaunch: the
/// window between picking a folder and the first pass that finishes is exactly when a quit, a
/// crash or an unavailable folder would otherwise turn the upgrade into an ordinary merge.
struct NoteFolderAdoption {
    static let key = "note.folder-sync.adoption-pending"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var pass: NoteFolderPass { defaults.bool(forKey: Self.key) ? .adoption : .steady }

    /// Every choice is an adoption, including re-picking a folder this Mac has seen before.
    func begin() {
        defaults.set(true, forKey: Self.key)
    }

    /// Only ever called past every write of a pass that finished. A failed or partial pass must
    /// leave the flag set, so the next one still keeps both sides of a divergence.
    func finish() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// How the chosen folder is remembered and its access held open: the Mac keeps a path and needs no token, iOS a security-scoped bookmark whose access stays open while the folder is in use.
struct NoteFolderLocation {
    enum Saved: Equatable {
        case none
        case folder(URL)
        /// A folder was chosen and what was saved no longer leads to it; never read as "no folder".
        case unresolvable
    }

    static let pathKey = "note.folder-sync.path"
    static let bookmarkKey = "note.folder-sync.bookmark"

    let load: () -> Saved
    /// Remembers the folder and returns the URL to use for it from now on.
    let save: (URL) throws -> URL
    let clear: () -> Void
    /// Opens access to the folder; the closure it returns closes that access again.
    let access: (URL) -> () -> Void

    static func path(defaults: UserDefaults) -> Self {
        Self(
            load: {
                defaults.string(forKey: pathKey).map { .folder(URL(fileURLWithPath: $0)) } ?? .none
            },
            save: { url in
                let folder = url.standardizedFileURL
                defaults.set(folder.path, forKey: pathKey)
                return folder
            },
            clear: { defaults.removeObject(forKey: pathKey) },
            access: { _ in {} })
    }

    /// A bookmark that stops resolving is kept, so a provider that is not ready yet can resolve on a later start; only a new choice or a disconnect forgets it.
    static func bookmark(defaults: UserDefaults) -> Self {
        Self(
            load: {
                guard let data = defaults.data(forKey: bookmarkKey) else { return .none }
                var isStale = false
                guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
                else { return .unresolvable }
                if isStale {
                    let close = scopedAccess(to: url)
                    defer { close() }
                    if let fresh = try? url.bookmarkData() { defaults.set(fresh, forKey: bookmarkKey) }
                }
                return .folder(url)
            },
            save: { url in
                // A picked URL carries its grant only while accessed, and the bookmark must be made then.
                let close = scopedAccess(to: url)
                defer { close() }
                let data = try url.bookmarkData()
                var isStale = false
                let resolved = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
                defaults.set(data, forKey: bookmarkKey)
                return resolved
            },
            clear: { defaults.removeObject(forKey: bookmarkKey) },
            access: scopedAccess)
    }

    /// `false` only means the URL carries no scope of its own, so it is balanced rather than failed.
    private static func scopedAccess(to url: URL) -> () -> Void {
        let isScoped = url.startAccessingSecurityScopedResource()
        return { if isScoped { url.stopAccessingSecurityScopedResource() } }
    }
}

/// The folder's one-line status. `device` is the only wording that differs between platforms.
enum NoteFolderStatus {
    static func text(
        error: String?, isConnected: Bool, isUnavailable: Bool, isWorking: Bool,
        pendingDownloads: Int, lastSyncedAt: Date?, device: String
    ) -> String {
        if let error { return error }
        guard isConnected else {
            return isUnavailable
                ? "The Notes folder can’t be found · Notes stay on \(device) until you choose it again"
                : "Off · Notes stay on \(device)"
        }
        if isWorking { return "Syncing…" }
        if pendingDownloads > 0 {
            return "Waiting for \(pendingDownloads) file\(pendingDownloads == 1 ? "" : "s") to become available…"
        }
        guard let lastSyncedAt else { return "Waiting for the folder…" }
        return "Up to date · " + lastSyncedAt.formatted(date: .omitted, time: .shortened)
    }
}
