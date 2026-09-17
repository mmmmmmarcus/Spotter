import Darwin
import Foundation

enum AppFileResources {
    static func targetLimit(current: rlim_t, hard: rlim_t) -> rlim_t {
        max(current, min(hard, rlim_t(OPEN_MAX), 4096))
    }

    @discardableResult
    static func prepare() throws -> rlimit {
        var limits = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limits) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let target = targetLimit(current: limits.rlim_cur, hard: limits.rlim_max)
        if target > limits.rlim_cur {
            limits.rlim_cur = target
            guard setrlimit(RLIMIT_NOFILE, &limits) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return limits
    }

    struct Snapshot: Sendable {
        let count: Int
        let limit: UInt64
        let types: [UInt32: Int]

        var summary: String {
            let breakdown = types.keys.sorted().map { "type\($0)=\(types[$0]!)" }.joined(separator: ", ")
            return "Open descriptors: \(count)/\(limit); \(breakdown)"
        }
    }

    static func snapshot() -> Snapshot? {
        var limits = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limits) == 0 else { return nil }
        let required = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        guard required > 0 else { return nil }
        // Leave room for descriptors opened between the size query and the actual read.
        let capacity = Int(required) / MemoryLayout<proc_fdinfo>.stride + 64
        var entries = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let bytes = entries.withUnsafeMutableBytes {
            proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return nil }
        let count = min(Int(bytes) / MemoryLayout<proc_fdinfo>.stride, capacity)
        var types: [UInt32: Int] = [:]
        for entry in entries.prefix(count) { types[entry.proc_fdtype, default: 0] += 1 }
        return Snapshot(count: count, limit: limits.rlim_cur, types: types)
    }
}
