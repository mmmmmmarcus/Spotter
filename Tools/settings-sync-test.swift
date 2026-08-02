import Foundation

@main
struct SettingsSyncTests {
    static func main() async throws {
        var revision = SettingsSyncRevision()
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        precondition(!revision.isCurrent(first))
        revision.record(first)
        precondition(revision.isCurrent(first))
        precondition(!revision.isCurrent(second))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotter-settings-sync-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("Settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let io = SettingsSyncFileIO()
        try await io.write(first, to: file)
        let firstRead = try await io.read(from: file)
        precondition(firstRead == first)
        try await io.write(second, to: file)
        let secondRead = try await io.read(from: file)
        precondition(secondRead == second)
        precondition(FileManager.default.fileExists(atPath: file.path))

        let changed = DispatchSemaphore(value: 0)
        let watcher = SettingsSyncFileWatcher(url: file) { changed.signal() }
        try Data("external replacement".utf8).write(to: file, options: .atomic)
        let observed = await Task.detached {
            waitForChange(changed)
        }.value
        watcher.stop()
        precondition(observed)
        print("Settings Sync: ALL PASSED")
    }

    private static func waitForChange(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 3) == .success
    }
}
