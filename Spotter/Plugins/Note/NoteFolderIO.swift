import Foundation

/// Reads and writes the Notes folder under `NSFileCoordinator`, the way `SettingsSyncManager` does
/// for its single file. Nothing here decides policy: `NoteFolderReconciler` does, and this actor
/// only performs the plan it produced.
actor NoteFolderIO {
    enum Failure: LocalizedError {
        case unreachable(String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let path): "The Notes folder isn’t available (\(path))."
            }
        }
    }

    /// A removed Note file goes to the Trash so the bytes stay recoverable. Harnesses turn it off
    /// rather than filling the running user's Trash with fixtures.
    private let trashesRemovedFiles: Bool

    init(trashesRemovedFiles: Bool = true) {
        self.trashesRemovedFiles = trashesRemovedFiles
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .isUbiquitousItemKey,
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
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw Failure.unreachable(folder.path) }

        for name in plan.removals.keys.sorted() {
            try remove(folder.appendingPathComponent(name))
        }
        // Two moves rather than one: a straight rename can collide with a file that is itself about
        // to move. A crash between the halves leaves `~<uuid>.md`, still a well-formed Note file the
        // next scan renames into place.
        let moving = plan.placements.filter(\.needsMove)
        for placement in moving {
            guard let current = placement.currentName else { continue }
            try move(
                folder.appendingPathComponent(current),
                to: folder.appendingPathComponent(NoteFolderFormat.temporaryName(for: placement.id)))
        }
        for placement in moving {
            try move(
                folder.appendingPathComponent(NoteFolderFormat.temporaryName(for: placement.id)),
                to: folder.appendingPathComponent(placement.desiredName))
        }
        for placement in plan.placements where placement.needsWrite {
            try write(
                Data(placement.contents.utf8),
                to: folder.appendingPathComponent(placement.desiredName))
        }
        if let tombstones = plan.ledger {
            let data = try NoteFolderLedger(tombstones: tombstones).encoded()
            try write(data, to: folder.appendingPathComponent(NoteFolderFormat.ledgerFileName))
        }
    }

    private func readContents(of folder: URL) throws -> NoteFolderScan {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsSubdirectoryDescendants])
        var files: [NoteFolderFile] = []
        var ledger: NoteFolderLedgerState = .missing
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(Self.resourceKeys))
            if values?.isDirectory == true { continue }
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
                ledger = readLedger(at: entry, downloaded: downloaded)
                continue
            }
            guard NoteFolderFormat.isNoteFileName(name) else { continue }
            guard downloaded, let data = try? Data(contentsOf: entry),
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

    private func readLedger(at url: URL, downloaded: Bool) -> NoteFolderLedgerState {
        guard downloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return .unavailable
        }
        guard let data = try? Data(contentsOf: url),
            let decoded = try? NoteFolderLedger(json: data)
        else { return .unavailable }
        return .readable(decoded.tombstones)
    }

    private func isDownloaded(_ values: URLResourceValues?) -> Bool {
        guard values?.isUbiquitousItem == true else { return true }
        guard let status = values?.ubiquitousItemDownloadingStatus else { return true }
        return status == .current
    }

    /// `.Groceries.md.icloud` names the not-yet-downloaded `Groceries.md`.
    private func placeholderTarget(of name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    private func write(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            do { try data.write(to: coordinatedURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func move(_ from: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(
            writingItemAt: from, options: .forMoving, writingItemAt: destination,
            options: .forReplacing, error: &coordinationError
        ) { source, target in
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: source)
                } else {
                    try FileManager.default.moveItem(at: source, to: target)
                }
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    /// Deleted Note files go to the Trash, not into thin air: the ledger already records the
    /// deletion, so the only thing left to decide is whether the bytes are recoverable.
    private func remove(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var removeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) {
            coordinatedURL in
            do {
                if trashesRemovedFiles {
                    try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: coordinatedURL)
                }
            } catch {
                do { try FileManager.default.removeItem(at: coordinatedURL) } catch {
                    removeError = error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        if let removeError { throw removeError }
    }
}
