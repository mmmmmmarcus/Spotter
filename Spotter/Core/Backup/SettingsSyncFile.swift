import CryptoKit
import Darwin
import Foundation

/// Byte identity suppresses notifications caused by our own canonical coordinated writes.
struct CoordinatedFileRevision: Equatable, Sendable {
    private var digest: SHA256.Digest?

    func isCurrent(_ candidate: Data) -> Bool {
        digest == SHA256.hash(data: candidate)
    }

    mutating func record(_ candidate: Data) {
        digest = SHA256.hash(data: candidate)
    }

    static func fingerprint(_ candidate: Data) async -> Self {
        await Task.detached(priority: .utility) {
            var revision = Self()
            revision.record(candidate)
            return revision
        }.value
    }
}

/// Serializes coordinated reads and writes so an iCloud download cannot race a local settings save.
actor CoordinatedFileIO {
    private struct Stamp: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ url: URL) throws {
            var value = stat()
            guard stat(url.path, &value) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            device = value.st_dev
            inode = value.st_ino
            size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private var stamps: [URL: Stamp] = [:]

    func read(from url: URL) throws -> Data {
        try coordinatedRead(from: url, onlyIfChanged: false)!
    }

    func readIfChanged(from url: URL) throws -> Data? {
        try coordinatedRead(from: url, onlyIfChanged: true)
    }

    private func coordinatedRead(from url: URL, onlyIfChanged: Bool) throws -> Data? {
        try Task.checkCancellation()
        if onlyIfChanged, let known = stamps[url], (try? Stamp(url)) == known { return nil }
        if FileManager.default.isUbiquitousItem(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data?, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            result = Result {
                try Task.checkCancellation()
                let before = try Stamp(coordinatedURL)
                if onlyIfChanged, stamps[url] == before { return nil }
                let data = try Data(contentsOf: coordinatedURL)
                let after = try Stamp(coordinatedURL)
                stamps[url] = before == after ? after : nil
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    func invalidate(_ url: URL) {
        stamps[url] = nil
    }

    func write(_ data: Data, to url: URL) throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            do {
                try Task.checkCancellation()
                try data.write(to: coordinatedURL, options: .atomic)
                stamps[url] = try? Stamp(coordinatedURL)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}

/// NSFilePresenter catches coordinated iCloud changes; the directory source also catches uncoordinated editors and atomic file replacement.
final class CoordinatedFileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue

    private let onChange: @MainActor @Sendable () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var isRegistered = false

    /// A folder presenter watches the folder itself rather than its parent, and hears about its
    /// children through `presentedSubitemDidChange`.
    init(url: URL, isDirectory: Bool = false, onChange: @escaping @MainActor @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        let queue = OperationQueue()
        queue.name = "Spotter Coordinated File Presenter"
        queue.maxConcurrentOperationCount = 1
        presentedItemOperationQueue = queue
        super.init()
        NSFileCoordinator.addFilePresenter(self)
        isRegistered = true
        startDirectoryWatcher(for: isDirectory ? url : url.deletingLastPathComponent())
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

    func presentedSubitemDidChange(at url: URL) {
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
