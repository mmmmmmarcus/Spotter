import AppKit
import Combine
import Foundation

@main
@MainActor
struct SFSymbolTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ value: Bool, _ message: String) {
        if value { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<1500 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        expect(false, "asynchronous symbol operation finishes")
    }

    static func main() async throws {
        let fixture = Data(#"[{"name":"heart","codepoint":"U+1002B4","availability":{"monochrome":{"macOS":"11.0"}}},{"name":"heart.fill"},{"name":"heart"},{"name":"bad\"name"}]"#.utf8)
        let entries = try SFSymbolCatalog.decode(fixture)
        expect(entries.map(\.name) == ["heart", "heart.fill"], "CLI ranking is preserved while duplicate and unsafe names are rejected")
        expect(entries[0].minimumMacOS == "11.0" && entries[0].codepoint == "U+1002B4", "CLI availability and code point are retained")
        expect(entries[0].swiftUI == "Image(systemName: \"heart\")", "SwiftUI copy uses the original symbol name")
        for invalid in ["", "foo/bar", "foo; echo hello", "a\nb", "\"", String(repeating: "x", count: 257)] {
            expect(!SFSymbolCatalog.validName(invalid), "hostile names cannot enter copy or export")
        }
        for data in [Data("invalid".utf8), Data("{}".utf8), Data(#"[{"name":1}]"#.utf8), Data(repeating: 0, count: 4 * 1024 * 1024 + 1)] {
            do { _ = try SFSymbolCatalog.decode(data); expect(false, "malformed or oversized CLI output fails") }
            catch { expect(true, "malformed or oversized CLI output fails explicitly") }
        }
        expect(try SFSymbolCatalog.decode(Data("[]".utf8)).isEmpty, "zero matches are a valid result")
        let args = try SFSymbolCatalog.searchArguments(" --help; $(touch marker) ")
        expect(args.suffix(2) == ["--", "--help; $(touch marker)"], "query is one literal argument after the option terminator")
        do { _ = try SFSymbolCatalog.searchArguments(String(repeating: "a", count: 257)); expect(false, "oversized query rejected") }
        catch { expect(true, "oversized query rejected") }
        expect(SFSymbolCatalog.argument("sf heart fill") == "heart fill"
            && SFSymbolCatalog.argument("SF Symbols heart") == "heart"
            && SFSymbolCatalog.argument("sfsymbols search") == "search"
            && SFSymbolCatalog.argument("safari heart") == nil, "launcher prefixes claim only SF Symbols commands")
        await store(entries: entries)
        try await process()
        let executable = URL(fileURLWithPath: "/Applications/SF Symbols.app/Contents/Executables/sfsymbols")
        if FileManager.default.isExecutableFile(atPath: executable.path) { try await installed(executable) }
        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func store(entries: [SFSymbolEntry]) async {
        let store = SFSymbolStore { _, query in
            try await Task.sleep(for: .milliseconds(30))
            return entries.filter { query.isEmpty || $0.name == query }
        }
        store.start(executable: nil)
        expect(store.errorMessage != nil && !store.isLoading, "missing CLI reports an update instruction")
        store.start(executable: URL(fileURLWithPath: "/fixture"))
        let queries = CurrentValueSubject<String, Never>("heart")
        store.observe(queries)
        await waitUntil { !store.isLoading }
        expect(store.results.map(\.name) == ["heart"], "current query drives the CLI search")
        queries.send("heart")
        queries.send("heart.fill")
        await waitUntil { store.results.first?.name == "heart.fill" }
        expect(store.entry(id: "heart.fill")?.name == "heart.fill", "actions resolve the currently displayed symbol")
        let before = store.results
        queries.send("heart")
        store.stop()
        try? await Task.sleep(for: .milliseconds(200))
        expect(store.results == before, "closing cancels pending query publication")
        store.start(executable: URL(fileURLWithPath: "/fixture"))
        store.stop()
        try? await Task.sleep(for: .milliseconds(200))
        expect(store.results.isEmpty && !store.isLoading, "closing before search starts leaves no pending results")
        let failed = SFSymbolStore { _, _ in throw SFSymbolCatalog.Failure(message: "fixture failure") }
        failed.start(executable: URL(fileURLWithPath: "/fixture"))
        await waitUntil { !failed.isLoading }
        expect(failed.errorMessage == "fixture failure" && failed.results.isEmpty, "CLI errors reach the palette")
    }

    static func process() async throws {
        let data = try await SFSymbolCLI.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "--help; $(touch marker)"])
        expect(String(decoding: data, as: UTF8.self) == "--help; $(touch marker)", "process transport never invokes a shell")
        do {
            _ = try await SFSymbolCLI.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo fixture-error >&2; exit 7"])
            expect(false, "nonzero exit fails")
        } catch { expect(error.localizedDescription.contains("fixture-error"), "nonzero exit preserves stderr") }
        let started = Date()
        do {
            _ = try await SFSymbolCLI.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], timeout: 0.1)
            expect(false, "process timeout fails")
        } catch { expect(error.localizedDescription.contains("timed out") && Date().timeIntervalSince(started) < 3, "timeout terminates the owned process promptly") }
        let task = Task { try await SFSymbolCLI.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; expect(false, "cancellation fails") }
        catch { expect(error is CancellationError, "cancellation terminates the in-flight CLI") }
    }

    static func installed(_ executable: URL) async throws {
        let found = try await SFSymbolCLI.search(executable: executable, query: "heart.fill")
        expect(found.first?.name == "heart.fill", "real Apple CLI exact search")
        let initial = try await SFSymbolCLI.search(executable: executable, query: "")
        expect(initial.count == SFSymbolCatalog.resultLimit, "real CLI supplies a bounded initial catalog")
        let png = try await SFSymbolCLI.export(executable: executable, name: "heart.fill", format: "png")
        let bitmap = NSBitmapImageRep(data: png)
        expect((bitmap?.pixelsWide ?? 0) > 100 && (bitmap?.pixelsHigh ?? 0) > 100, "real CLI exports a PNG image")
        expect(bitmap?.colorAt(x: 0, y: 0)?.alphaComponent == 0, "PNG retains transparent background")
        let svg = try await SFSymbolCLI.export(executable: executable, name: "heart.fill", format: "svg")
        let text = String(decoding: svg, as: UTF8.self)
        expect(text.contains("<svg") && text.contains("<path"), "real CLI exports a vector SVG template")
    }
}
