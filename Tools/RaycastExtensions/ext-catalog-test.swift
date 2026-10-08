import Foundation

@main
struct ExtensionCatalogTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("installed")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let manifest = #"{"name":"fixture","title":"Fixture","commands":[{"name":"run","title":"Run","mode":"view"}]}"#
        try Data(manifest.utf8).write(to: source.appendingPathComponent("package.json"))
        let bundle = source.appendingPathComponent("run.js")
        try Data("first".utf8).write(to: bundle)
        let first = try ExtensionCatalog.install(from: source, destinationRoot: destination)
        let assets = first.directory.appendingPathComponent("assets")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1]).write(to: assets.appendingPathComponent("command.png"))
        try Data([2]).write(to: first.directory.appendingPathComponent("root.png"))
        precondition(first.artworkPath("command.png") == assets.appendingPathComponent("command.png").resolvingSymlinksInPath().path)
        precondition(first.artworkPath("root.png") == first.directory.appendingPathComponent("root.png").resolvingSymlinksInPath().path)
        precondition(first.artworkPath("missing.png") == nil)
        precondition(first.artworkPath("../../source/package.json") == nil)
        let firstContents = try String(contentsOf: first.directory.appendingPathComponent("run.js"), encoding: .utf8)
        precondition(firstContents == "first")
        try Data("second".utf8).write(to: bundle)
        let second = try ExtensionCatalog.install(from: source, destinationRoot: destination)
        let contents = try String(contentsOf: second.directory.appendingPathComponent("run.js"), encoding: .utf8)
        precondition(contents == "second")
        try fm.removeItem(at: bundle)
        do {
            _ = try ExtensionCatalog.install(from: source, destinationRoot: destination)
            fatalError("Incomplete update must fail")
        } catch ExtensionCatalog.InstallError.noBuiltCommands { }
        let preserved = try String(contentsOf: second.directory.appendingPathComponent("run.js"), encoding: .utf8)
        precondition(preserved == "second")
        let leftovers = try fm.contentsOfDirectory(atPath: destination.path)
        precondition(leftovers == ["fixture"])
        print("PASS catalog installation, replacement, failed update preservation and staging cleanup")
    }
}
