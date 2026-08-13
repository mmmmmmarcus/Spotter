import Foundation

struct MoleRunError: Error, Sendable {
    let message: String
}

/// Runs one Mole process off-main and interrupts it when the awaiting task is cancelled.
enum MoleProcessRunner {
    static func capture(
        path: String, arguments: [String], environment: [String: String] = [:],
        standardInput: Data? = nil,
        onOutput: (@Sendable (Data) -> Void)? = nil
    ) async -> Result<Data, MoleRunError> {
        let controller = MoleProcessController()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = arguments
                    process.environment = ProcessInfo.processInfo.environment.merging(environment) {
                        _, override in override
                    }
                    let out = Pipe()
                    process.standardOutput = out
                    process.standardError = out
                    let input = standardInput.map { _ in Pipe() }
                    if let input {
                        process.standardInput = input
                    } else {
                        process.standardInput = FileHandle.nullDevice
                    }

                    guard controller.attach(process) else {
                        continuation.resume(
                            returning: .failure(MoleRunError(message: "Mole scan cancelled.")))
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        controller.detach(process)
                        continuation.resume(
                            returning: .failure(
                                MoleRunError(
                                    message: "Couldn't run Mole: \(error.localizedDescription)")))
                        return
                    }

                    if let standardInput, let input {
                        input.fileHandleForWriting.write(standardInput)
                        try? input.fileHandleForWriting.close()
                    }

                    controller.interruptIfCancelled(process)
                    var data = Data()
                    var lastPublishedSize = 0
                    var lastPublishedTime: UInt64 = 0
                    while true {
                        let chunk = out.fileHandleForReading.availableData
                        guard !chunk.isEmpty else { break }
                        data.append(chunk)
                        let now = DispatchTime.now().uptimeNanoseconds
                        if onOutput != nil,
                            lastPublishedTime == 0 || now - lastPublishedTime >= 250_000_000
                        {
                            onOutput?(data)
                            lastPublishedSize = data.count
                            lastPublishedTime = now
                        }
                    }
                    if data.count > lastPublishedSize { onOutput?(data) }
                    process.waitUntilExit()
                    controller.detach(process)

                    if controller.isCancelled {
                        continuation.resume(
                            returning: .failure(MoleRunError(message: "Mole scan cancelled.")))
                    } else if process.terminationReason != .exit {
                        continuation.resume(
                            returning: .failure(
                                MoleRunError(message: "Mole was terminated before it finished.")))
                    } else if process.terminationStatus != 0 {
                        let detail = failureDetail(from: data)
                        let status = process.terminationStatus
                        let message = detail.map { "Mole exited with status \(status): \($0)" }
                            ?? "Mole exited with status \(status)."
                        continuation.resume(returning: .failure(MoleRunError(message: message)))
                    } else {
                        continuation.resume(returning: .success(data))
                    }
                }
            }
        } onCancel: {
            controller.cancel()
        }
    }

    private static func failureDetail(from data: Data) -> String? {
        let lines = MoleParser.stripANSI(String(decoding: data, as: UTF8.self))
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.allSatisfy { "=-_─".contains($0) } }
        let failureTerms = ["failed", "failure", "error", "aborted", "denied", "not found"]
        return lines.reversed().first { line in
            let lowered = line.lowercased()
            return failureTerms.contains(where: lowered.contains)
        } ?? lines.last
    }
}

/// Synchronizes task cancellation with Foundation's non-Sendable `Process` reference.
private final class MoleProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func attach(_ process: Process) -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            self.process = process
            return true
        }
    }

    func detach(_ process: Process) {
        lock.withLock {
            if self.process === process { self.process = nil }
        }
    }

    func cancel() {
        let active = lock.withLock { () -> Process? in
            cancelled = true
            return process
        }
        if active?.isRunning == true { active?.interrupt() }
    }

    func interruptIfCancelled(_ process: Process) {
        if isCancelled, process.isRunning { process.interrupt() }
    }
}
