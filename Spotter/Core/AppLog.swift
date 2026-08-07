import Foundation
import os

/// One diagnostic event, as shown in Settings → Diagnostics.
struct AppLogEntry: Identifiable, Equatable, Sendable {
    enum Level: String, Sendable {
        case info
        case error
    }

    let id: UUID
    let date: Date
    let level: Level
    let subsystem: String
    let message: String

    init(date: Date = Date(), level: Level, subsystem: String, message: String) {
        id = UUID()
        self.date = date
        self.level = level
        self.subsystem = subsystem
        self.message = message
    }

    var line: String {
        "\(Self.stamp.string(from: date)) [\(level.rawValue.uppercased())] \(subsystem): \(message)"
    }

    private nonisolated(unsafe) static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// The app-wide diagnostic sink: an in-memory ring buffer for the Diagnostics pane, a mirror into
/// `os.Logger` for Console.app, and a size-capped file for bug reports. Deliberately a singleton —
/// like `NotificationCenter.default` it is infrastructure every subsystem reaches, not feature
/// state, and threading a logger through every manager would be all churn and no safety.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [AppLogEntry] = []

    /// Enough history to debug a session without ever mattering for memory.
    private static let ringLimit = 500
    /// The on-disk cap per file; one rotation keeps the previous file for context.
    private static let fileLimit = 512 * 1024

    let fileURL: URL
    private var handle: FileHandle?
    private var bytesWritten: UInt64 = 0

    private init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.spotter.app"
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("spotter.log")
        openFile()
    }

    /// Callable from any isolation — the `os.Logger` line lands immediately, the ring/file on-main.
    nonisolated static func error(_ subsystem: String, _ message: String) {
        log(level: .error, subsystem: subsystem, message: message)
    }

    nonisolated static func info(_ subsystem: String, _ message: String) {
        log(level: .info, subsystem: subsystem, message: message)
    }

    private nonisolated static func log(
        level: AppLogEntry.Level, subsystem: String, message: String
    ) {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.spotter.app", category: subsystem)
        switch level {
        case .error: logger.error("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        }
        let entry = AppLogEntry(level: level, subsystem: subsystem, message: message)
        Task { @MainActor in shared.append(entry) }
    }

    var transcript: String {
        entries.map(\.line).joined(separator: "\n")
    }

    func clear() {
        entries = []
        handle?.truncateFile(atOffset: 0)
        bytesWritten = 0
    }

    private func append(_ entry: AppLogEntry) {
        entries.append(entry)
        if entries.count > Self.ringLimit {
            entries.removeFirst(entries.count - Self.ringLimit)
        }
        write(entry.line + "\n")
    }

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if bytesWritten + UInt64(data.count) > UInt64(Self.fileLimit) { rotate() }
        handle?.write(data)
        bytesWritten += UInt64(data.count)
    }

    /// Keeps exactly one previous file: enough context for a report, never unbounded growth.
    private func rotate() {
        try? handle?.close()
        handle = nil
        let previous = fileURL.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
        openFile()
    }

    private func openFile() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        bytesWritten = (try? handle?.seekToEnd()) ?? 0
    }
}
