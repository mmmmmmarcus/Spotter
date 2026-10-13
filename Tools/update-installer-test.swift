import Foundation
import Darwin

@main
struct UpdateInstallerTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Spotter.app")
        let staged = root.appendingPathComponent(".update-test-Spotter.app")
        for url in [installed, staged] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        let marker = "version"
        try Data("old".utf8).write(to: installed.appendingPathComponent(marker))
        try Data("new".utf8).write(to: staged.appendingPathComponent(marker))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["0.4"]
        try child.run()
        do {
            try UpdateInstaller.waitForExit(child.processIdentifier, timeout: 0.01)
            fatalError("A running process must not authorize replacement")
        } catch {}
        assert((try! String(contentsOf: installed.appendingPathComponent(marker), encoding: .utf8)) == "old")
        try UpdateInstaller.waitForExit(child.processIdentifier, timeout: 3)
        child.waitUntilExit()
        try UpdateInstaller.waitForExit(child.processIdentifier, timeout: 0.1)
        try UpdateInstaller.exchange(staged: staged, installed: installed)
        assert((try! String(contentsOf: installed.appendingPathComponent(marker), encoding: .utf8)) == "new")
        assert((try! String(contentsOf: staged.appendingPathComponent(marker), encoding: .utf8)) == "old")
        assert(!UpdateInstaller.validPaths(staged: installed, installed: installed))
        assert(!UpdateInstaller.validPaths(staged: root.appendingPathComponent("elsewhere/.update-test.app"), installed: installed))
        do {
            try UpdateInstaller.verify(staged, matches: installed)
            fatalError("Unsigned apps must be rejected")
        } catch {}
        try FileManager.default.removeItem(at: staged)
        do {
            try UpdateInstaller.exchange(staged: staged, installed: installed)
            fatalError("A missing stage must fail")
        } catch {}
        assert((try! String(contentsOf: installed.appendingPathComponent(marker), encoding: .utf8)) == "new")
        print("PASS: process-exit barrier, timeout preservation, atomic swap, invalid paths and signature rejection")
    }
}
