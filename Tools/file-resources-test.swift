import Darwin
import Foundation

@main
struct FileResourcesTests {
    static func capture(executable: String) throws {
        let process = Process()
        let output = Pipe()
        defer { output.closeHandles() }
        let errors = Pipe()
        defer { errors.closeHandles() }
        process.executableURL = URL(fileURLWithPath: executable)
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        _ = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
    }

    static func main() throws {
        precondition(AppFileResources.targetLimit(current: 256, hard: 1024) == 1024)
        precondition(AppFileResources.targetLimit(current: 256, hard: 256) == 256)
        precondition(AppFileResources.targetLimit(current: 8192, hard: 8192) == 8192)
        precondition(AppFileResources.targetLimit(current: 256, hard: UInt64(Int64.max)) == min(4096, rlim_t(OPEN_MAX)))
        let baseline = AppFileResources.snapshot()!.count
        for _ in 0..<300 {
            try capture(executable: "/usr/bin/true")
        }
        for _ in 0..<100 {
            do { try capture(executable: "/no-such-spotter-test-executable") }
            catch { }
        }
        precondition(AppFileResources.snapshot()!.count <= baseline + 4, "Success and launch failure must release pipes")
        var original = rlimit()
        precondition(getrlimit(RLIMIT_NOFILE, &original) == 0)
        defer { precondition(setrlimit(RLIMIT_NOFILE, &original) == 0) }
        var restricted = original
        restricted.rlim_cur = min(original.rlim_max, 128)
        precondition(setrlimit(RLIMIT_NOFILE, &restricted) == 0)
        var descriptors: [Int32] = []
        defer { for descriptor in descriptors { close(descriptor) } }
        while true {
            let descriptor = open("/dev/null", O_RDONLY)
            if descriptor < 0 { break }
            descriptors.append(descriptor)
        }
        precondition(errno == EMFILE)
        let prepared = try AppFileResources.prepare()
        precondition(prepared.rlim_max == original.rlim_max)
        precondition(prepared.rlim_cur == AppFileResources.targetLimit(current: restricted.rlim_cur, hard: original.rlim_max))
        if prepared.rlim_cur > restricted.rlim_cur {
            let extra = open("/dev/null", O_RDONLY)
            precondition(extra >= 0, "Resource headroom must permit rendering resources to open")
            close(extra)
            let snapshot = AppFileResources.snapshot()!
            precondition(snapshot.count >= descriptors.count)
            precondition(snapshot.types.values.reduce(0, +) == snapshot.count)
            let before = snapshot.count
            for _ in 0..<1000 { precondition(AppFileResources.snapshot() != nil) }
            precondition(AppFileResources.snapshot()!.count == before, "Diagnostics must not leak descriptors")
        }
        print("PASS: exhausted soft limit recovered; hard limit preserved; diagnostic sampling does not leak")
    }
}
