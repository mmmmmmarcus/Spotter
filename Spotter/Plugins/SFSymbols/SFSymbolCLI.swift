import Darwin
import Foundation

enum SFSymbolCLI {
    static func search(executable: URL, query: String) async throws -> [SFSymbolEntry] {
        let data = try await run(executable: executable, arguments: SFSymbolCatalog.searchArguments(query))
        return try SFSymbolCatalog.decode(data)
    }

    static func export(executable: URL, name: String, format: String) async throws -> Data {
        guard SFSymbolCatalog.validName(name), ["png", "svg"].contains(format) else {
            throw SFSymbolCatalog.Failure(message: "Invalid SF Symbol export.")
        }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("symbol." + format)
        _ = try await run(executable: executable,
            arguments: ["export", name, "--format", format, "--output", output.path,
                "--point-size", "128", "--image-scale", "2", "--rendering-mode", "monochrome", "--color", "black"], timeout: 30)
        let data = try boundedRead(output, limit: 16 * 1024 * 1024)
        guard !data.isEmpty else { throw SFSymbolCatalog.Failure(message: "SF Symbols exported an empty file.") }
        return data
    }

    static func run(executable: URL, arguments: [String], timeout: Double = 10) async throws -> Data {
        let operation = SFSymbolProcess()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try operation.execute(executable: executable, arguments: arguments, timeout: timeout) })
                }
            }
        } onCancel: { operation.cancel() }
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.spotter.app1")
            .appendingPathComponent("sf-symbols-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw SFSymbolCatalog.Failure(message: "SF Symbols returned too much data.") }
        return data
    }
}

private final class SFSymbolProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func cancel(timeout: Bool = false) {
        lock.withLock {
            cancelled = true
            timedOut = timeout
            // The CLI is a bounded read/export child with no interactive state to save.
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func execute(executable: URL, arguments: [String], timeout: Double) throws -> Data {
        let directory = try SFSymbolCLI.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdout = directory.appendingPathComponent("stdout")
        let stderr = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let output = try FileHandle(forWritingTo: stdout)
        defer { try? output.close() }
        let errors = try FileHandle(forWritingTo: stderr)
        defer { try? errors.close() }
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = errors
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            try child.run()
            process = child
        }
        let deadline = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        child.waitUntilExit()
        deadline.cancel()
        let interrupted = lock.withLock { () -> (Bool, Bool) in
            process = nil
            return (cancelled, timedOut)
        }
        if interrupted.1 { throw SFSymbolCatalog.Failure(message: "SF Symbols timed out. Try a more specific search.") }
        if interrupted.0 { throw CancellationError() }
        guard child.terminationReason == .exit, child.terminationStatus == 0 else {
            let detail = String(decoding: (try? SFSymbolCLI.boundedRead(stderr, limit: 8192)) ?? Data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SFSymbolCatalog.Failure(message: detail.isEmpty ? "SF Symbols exited with status \(child.terminationStatus)." : detail)
        }
        return try SFSymbolCLI.boundedRead(stdout, limit: 4 * 1024 * 1024)
    }
}
