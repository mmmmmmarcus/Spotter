import Foundation

struct MoleRunError: Error, Sendable {
    let message: String
}

/// Runs one Mole process off-main and interrupts it when the awaiting task is cancelled.
enum MoleProcessRunner {
    static func capture(
        path: String, arguments: [String], environment: [String: String] = [:],
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
                    process.standardError = FileHandle.nullDevice
                    process.standardInput = FileHandle.nullDevice

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
                    } else if data.isEmpty {
                        continuation.resume(
                            returning: .failure(MoleRunError(message: "Mole returned no output.")))
                    } else {
                        continuation.resume(returning: .success(data))
                    }
                }
            }
        } onCancel: {
            controller.cancel()
        }
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
