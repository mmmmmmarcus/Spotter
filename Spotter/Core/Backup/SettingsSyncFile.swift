import Darwin
import Foundation

/// Byte identity is enough for the small, canonical settings JSON and suppresses notifications caused by our own coordinated write.
struct SettingsSyncRevision: Sendable {
    private(set) var data: Data?

    func isCurrent(_ candidate: Data) -> Bool {
        data == candidate
    }

    mutating func record(_ candidate: Data) {
        data = candidate
    }
}

/// Serializes coordinated reads and writes so an iCloud download cannot race a local settings save.
actor SettingsSyncFileIO {
    func read(from url: URL) throws -> Data {
        if FileManager.default.isUbiquitousItem(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}

/// NSFilePresenter catches coordinated iCloud changes; the directory source also catches uncoordinated editors and atomic file replacement.
final class SettingsSyncFileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue

    private let onChange: @MainActor @Sendable () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var isRegistered = false

    init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        let queue = OperationQueue()
        queue.name = "Spotter Settings Sync Presenter"
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        super.init()
        NSFileCoordinator.addFilePresenter(self)
        isRegistered = true
        startDirectoryWatcher(for: url.deletingLastPathComponent())
    }

    func stop() {
        if isRegistered {
            NSFileCoordinator.removeFilePresenter(self)
            isRegistered = false
        }
        directorySource?.cancel()
        directorySource = nil
    }

    func presentedItemDidChange() {
        notify()
    }

    func presentedItemDidMove(to newURL: URL) {
        notify()
    }

    private func startDirectoryWatcher(for directory: URL) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link],
            queue: DispatchQueue.global(qos: .utility))
        source.setEventHandler { [weak self] in self?.notify() }
        source.setCancelHandler { Darwin.close(descriptor) }
        directorySource = source
        source.resume()
    }

    private func notify() {
        Task { @MainActor [onChange] in onChange() }
    }

    deinit {
        directorySource?.cancel()
        if isRegistered { NSFileCoordinator.removeFilePresenter(self) }
    }
}
