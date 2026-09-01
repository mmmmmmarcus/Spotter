import Foundation

struct OnePasswordRunError: Error, Sendable {
    let message: String
    /// True when the fix is unlocking 1Password, not reporting a failure.
    let isLocked: Bool
}

/// One pseudo-terminal kept for the app's lifetime and handed to every `op` as stdin. The desktop
/// app scopes CLI authorization to a terminal session, which `op` derives from the TTY it is
/// attached to — with no TTY, every invocation reads as a brand-new session and 1Password
/// re-prompts on each action. Sharing one long-lived PTY makes all of Spotter's calls one session:
/// authorize once, then only 1Password's own inactivity and 12-hour caps apply. Only stdin is the
/// PTY — stdout and stderr stay captured pipes, so the secret/error separation is untouched.
private enum OnePasswordSessionTTY {
    static let slave: FileHandle? = {
        // O_NOCTTY throughout: Spotter itself must never adopt this as its controlling terminal.
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { return nil }
        guard grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            close(master)
            return nil
        }
        let slaveDescriptor = open(name, O_RDWR | O_NOCTTY)
        guard slaveDescriptor >= 0 else {
            close(master)
            return nil
        }
        // The master half is deliberately left open forever: closing it would hang up the slave.
        return FileHandle(fileDescriptor: slaveDescriptor, closeOnDealloc: false)
    }()
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
                    // The shared session TTY (see OnePasswordSessionTTY); a PTY that failed to open degrades to the old null stdin and per-call prompts.
                    process.standardInput = OnePasswordSessionTTY.slave ?? FileHandle.nullDevice
                    // `op` sees a TTY on stdin now; keep any diagnostics it colors for terminals out of the error text.
                    var environment = ProcessInfo.processInfo.environment
                    environment["NO_COLOR"] = "1"
                    process.environment = environment

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
