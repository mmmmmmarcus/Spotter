import Foundation

struct OnePasswordRunError: Error, Sendable {
    let message: String
    /// True when the fix is unlocking 1Password, not reporting a failure.
    let isLocked: Bool
}

/// Runs one `op` process off-main and interrupts it when the awaiting task is cancelled.
/// Unlike Mole's runner, stdout and stderr stay separate: stdout may be a secret and is returned
/// verbatim, stderr is only ever distilled into an error message and never logged with a secret.
enum OnePasswordProcessRunner {
    static func capture(
        path: String, arguments: [String]
    ) async -> Result<Data, OnePasswordRunError> {
        let controller = OnePasswordProcessController()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = arguments
                    let out = Pipe()
                    let err = Pipe()
                    process.standardOutput = out
                    process.standardError = err
                    process.standardInput = FileHandle.nullDevice

                    guard controller.attach(process) else {
                        continuation.resume(
                            returning: .failure(
                                OnePasswordRunError(
                                    message: "1Password request cancelled.", isLocked: false)))
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        controller.detach(process)
                        continuation.resume(
                            returning: .failure(
                                OnePasswordRunError(
                                    message:
                                        "Couldn't run the 1Password CLI: \(error.localizedDescription)",
                                    isLocked: false)))
                        return
                    }

                    controller.interruptIfCancelled(process)
                    // stderr drains on its own queue so a chatty diagnostic stream can't deadlock the stdout read.
                    nonisolated(unsafe) var stderrData = Data()
                    let stderrDrained = DispatchSemaphore(value: 0)
                    DispatchQueue.global(qos: .utility).async {
                        stderrData = err.fileHandleForReading.readDataToEndOfFile()
                        stderrDrained.signal()
                    }
                    var data = Data()
                    while true {
                        let chunk = out.fileHandleForReading.availableData
                        guard !chunk.isEmpty else { break }
                        data.append(chunk)
                    }
                    process.waitUntilExit()
                    stderrDrained.wait()
                    controller.detach(process)

                    let stderrText = String(decoding: stderrData, as: UTF8.self)
                    if controller.isCancelled {
                        continuation.resume(
                            returning: .failure(
                                OnePasswordRunError(
                                    message: "1Password request cancelled.", isLocked: false)))
                    } else if process.terminationReason != .exit {
                        continuation.resume(
                            returning: .failure(
                                OnePasswordRunError(
                                    message: "The 1Password CLI was terminated before it finished.",
                                    isLocked: false)))
                    } else if process.terminationStatus != 0 {
                        let message = OnePasswordParser.errorMessage(fromStderr: stderrText)
                        continuation.resume(
                            returning: .failure(
                                OnePasswordRunError(
                                    message: message,
                                    isLocked: OnePasswordParser.indicatesLockedSession(message))))
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
private final class OnePasswordProcessController: @unchecked Sendable {
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
