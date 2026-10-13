import Foundation
import Darwin
import Security

enum UpdateInstaller {
    // The outgoing app launches the incoming executable with this protocol; preserve it across releases.
    static let argument = "--spotter-install-update-v1"

    static func validPaths(staged: URL, installed: URL) -> Bool {
        staged.deletingLastPathComponent().standardizedFileURL == installed.deletingLastPathComponent().standardizedFileURL
            && installed.pathExtension == "app" && staged.pathExtension == "app"
            && staged.lastPathComponent.hasPrefix(".update-")
            && staged.standardizedFileURL != installed.standardizedFileURL
    }

    static func waitForExit(_ pid: pid_t, timeout: TimeInterval) throws {
        let queue = kqueue()
        guard queue >= 0 else { throw failure("Cannot watch the running application.") }
        defer { close(queue) }
        var event = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ENABLE),
            fflags: UInt32(NOTE_EXIT), data: 0, udata: nil)
        guard kevent(queue, &event, 1, nil, 0, nil) == 0 else {
            if errno == ESRCH { return }
            throw failure("Cannot watch the running application (errno \(errno)).")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw failure("Spotter did not exit; the installed app was kept.") }
            var interval = timespec(tv_sec: Int(remaining), tv_nsec: Int((remaining.truncatingRemainder(dividingBy: 1)) * 1_000_000_000))
            var notification = kevent()
            let count = kevent(queue, nil, 0, &notification, 1, &interval)
            if count == 1, notification.fflags & UInt32(NOTE_EXIT) != 0 { return }
            if count < 0, errno == EINTR { continue }
            throw failure("Timed out waiting for Spotter to exit; the installed app was kept.")
        }
    }

    static func exchange(staged: URL, installed: URL) throws {
        guard validPaths(staged: staged, installed: installed) else { throw failure("Invalid installation paths.") }
        let result = staged.path.withCString { source in
            installed.path.withCString { destination in renamex_np(source, destination, UInt32(RENAME_SWAP)) }
        }
        guard result == 0 else { throw failure("Atomic replacement failed (errno \(errno)); the installed app was kept.") }
    }

    static func verify(_ staged: URL, matches installed: URL) throws {
        var current: SecStaticCode?
        var incoming: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(installed as CFURL, [], &current) == errSecSuccess,
            let current, SecCodeCopyDesignatedRequirement(current, [], &requirement) == errSecSuccess,
            let requirement, SecStaticCodeCreateWithPath(staged as CFURL, [], &incoming) == errSecSuccess,
            let incoming, SecStaticCodeCheckValidity(incoming,
                SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), requirement) == errSecSuccess
        else { throw failure("The replacement does not match the installed signing identity.") }
    }

    static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 7, let pid = Int32(arguments[2]), pid > 1, pid != getpid() else { return 1 }
        let installed = URL(fileURLWithPath: arguments[3])
        let staged = URL(fileURLWithPath: arguments[4])
        let ready = URL(fileURLWithPath: arguments[5])
        let log = URL(fileURLWithPath: arguments[6])
        func report(_ message: String) { try? Data(message.utf8).write(to: log, options: .atomic) }
        var swapped = false
        defer { try? FileManager.default.removeItem(at: ready) }
        do {
            guard validPaths(staged: staged, installed: installed), getppid() == pid else { throw failure("Invalid update handoff.") }
            try verify(staged, matches: installed)
            try Data("ready".utf8).write(to: ready, options: .atomic)
            report("Waiting for the old Spotter process to exit.")
            try waitForExit(pid, timeout: 120)
            try verify(staged, matches: installed)
            try exchange(staged: staged, installed: installed)
            swapped = true
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launcher.arguments = ["-n", installed.path]
            try launcher.run()
            launcher.waitUntilExit()
            guard launcher.terminationStatus == 0 else { throw failure("The replacement is installed but relaunch failed. Open Spotter from Applications.") }
            try? FileManager.default.removeItem(at: staged)
            report("Update completed after the old process exited; replacement relaunched and retired bundle cleaned up.")
            return 0
        } catch {
            report("Update failed: \(error.localizedDescription)" + (swapped ? " The new app remains installed." : " The installed app was not replaced."))
            return 1
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Spotter.UpdateInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
