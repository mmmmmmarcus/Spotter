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

    private let trash: @Sendable (URL) throws -> Void

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

    func apply(_ plan: NoteFolderPlan, in folder: URL) throws {
        try performApply(plan, in: folder)
    }

    private nonisolated func performApply(_ plan: NoteFolderPlan, in folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw Failure.unreachable(folder.path) }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.prepare(forReadingItemsAt: [], options: [], writingItemsAt: [folder], options: [],
            error: &coordinationError) { finished in
            defer { finished() }
            result = Result {
                let current = try readContents(of: folder)
                let expected = plan.observed.files.sorted { $0.name < $1.name }
                guard current.files.sorted(by: { $0.name < $1.name }) == expected,
                    current.ledger == plan.observed.ledger
                else { throw Failure.changedDuringSync }
                try applyCoordinated(plan, in: folder, coordinator: coordinator)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private nonisolated func applyCoordinated(_ plan: NoteFolderPlan, in folder: URL, coordinator: NSFileCoordinator) throws {
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
                try coordinateWrite(url, options: .forDeleting, coordinator: coordinator) { target in
                    try requireContents(original, at: target)
                    try trash(target)
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
