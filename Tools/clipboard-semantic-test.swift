import Foundation
import CryptoKit

enum AppLog {
    static func error(_ subsystem: String, _ message: String) {}
}

@main
@MainActor
struct ClipboardSemanticTests {
    static var count = 0

    static func expect(_ value: Bool, _ message: String) {
        precondition(value, message)
        count += 1
    }

    static func vector(_ axis: Int) -> [Float] {
        var result = [Float](repeating: 0, count: ClipboardSemanticEngine.dimension)
        result[axis] = 1
        return result
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spotter-semantic-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), other = UUID()
        let entry = ClipboardSemanticEntry(id: id, fingerprint: "first", vectors: [vector(0), vector(2)])
        let unrelated = ClipboardSemanticEntry(id: other, fingerprint: "other", vectors: [vector(1)])
        expect(ClipboardSemanticEngine.ranked(query: vector(0), entries: [unrelated, entry]) == [id], "meaning ranking excludes orthogonal entries")
        expect(ClipboardSemanticEngine.ranked(query: vector(2), entries: [entry]) == [id], "later passages are searchable")
        expect(ClipboardSemanticEngine.normalized([Float.nan]) == nil, "malformed vectors rejected")
        expect(ClipboardSemanticEngine.normalized([Float](repeating: 0, count: 768)) == nil, "zero vectors rejected")
        expect(ClipboardSemanticEngine.ranked(query: [], entries: [entry]).isEmpty, "malformed queries rejected")
        expect(ClipboardSemanticSnapshot(model: "old model", entries: [entry]).compatibleEntries.isEmpty, "different model versions never mix")
        let texts = ClipboardSemanticEngine.documents(String(repeating: "苹果🍎 ", count: 4_000) + "Final message")
        expect(texts.count > 1 && texts.last!.contains("Final message"), "Unicode long clips keep their final passage")
        expect(texts.allSatisfy { $0.count <= 1_220 }, "passages are bounded")
        expect(ClipboardSemanticEngine.documents(String(repeating: "x", count: 100_000)).count == 32, "oversized clips are bounded")

        let folder = root.appendingPathComponent("Index")
        let index = ClipboardSemanticIndex(directory: folder)
        try await index.save(entry)
        try await index.save(unrelated)
        expect(await index.search(vector(0)) == [id], "saved embeddings are searchable")
        let reopened = ClipboardSemanticIndex(directory: folder)
        try await reopened.reconcile([id: "first", other: "changed"])
        expect(await reopened.indexed() == [id: "first"], "restart restores valid entries and drops changed content")
        await reopened.remove(id)
        expect(await reopened.search(vector(0)).isEmpty, "deletion removes search hits")
        try await reopened.save(entry)
        try await reopened.reconcile([:])
        expect(await reopened.indexed().isEmpty, "pruning removes stale entries")
        try await reopened.save(entry)
        try await reopened.clear()
        expect(!FileManager.default.fileExists(atPath: folder.path), "clear removes the persisted index")

        let store = ClipboardStore(directory: root.appendingPathComponent("Clipboard"))
        store.addText("exact invoice code ABC-123", sourceBundleID: nil)
        let exact = store.items[0]
        store.addText("receipt for the train journey", sourceBundleID: nil)
        let semantic = store.items[0]
        store.setSemanticMatches(query: "invoice", ids: [semantic.id])
        expect(store.search("invoice").map(\.id) == [exact.id, semantic.id], "exact matches lead semantic matches")
        expect(store.semanticOnlyIDs == [semantic.id], "only semantic-only matches get the related label")
        expect(store.search("other query").isEmpty, "stale query results never leak")
        store.setSemanticMatches(query: "invoice", ids: [exact.id, semantic.id])
        expect(store.search("invoice").count == 2, "hybrid results deduplicate exact matches")
        expect(store.search("invoice", filter: .image).isEmpty, "type filters apply to semantic results")
        store.togglePinned(semantic)
        expect(store.search("invoice").first?.id == semantic.id, "pins retain their existing priority")
        store.remove(semantic)
        expect(store.search("invoice").map(\.id) == [exact.id], "deleted rows cannot be resurrected by stale embedding results")
        store.clearAll()
        expect(store.search("invoice").isEmpty, "clear hides stale search results immediately")

        let validFile = root.appendingPathComponent("checksum")
        try Data("hello".utf8).write(to: validFile)
        let checksum = SHA256.hash(data: Data("hello".utf8)).map { String(format: "%02x", $0) }.joined()
        expect(try ClipboardSemanticModels.valid(validFile, file: .init(name: "test", bytes: 5, sha256: checksum)), "download checksum accepts exact bytes")
        expect(try !ClipboardSemanticModels.valid(validFile, file: .init(name: "test", bytes: 5, sha256: "bad")), "download checksum rejects corruption")

        let helper = root.appendingPathComponent("fixture-helper")
        let encoded = vector(0).withUnsafeBufferPointer { Data(buffer: $0).base64EncodedString() }
        let fixture = """
        #!/usr/bin/python3
        import sys, json, time
        print(json.dumps({'ready':True,'info':{'dim':768}}), flush=True)
        for line in sys.stdin:
            q=json.loads(line)
            if q['op']=='quit': break
            value=q['inputs'][0]
            if value=='slow': time.sleep(20)
            dim=3 if value=='bad' else 768
            print(json.dumps({'id':q['id'],'ok':True,'dim':dim,'vectors':'\(encoded)','errors':[None]}), flush=True)
        """
        try fixture.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let client = ClipboardEmbeddingClient(executable: helper, models: root)
        let response = try await client.embed([.init(value: "中文 and quotes ' ; $(nothing)", isImage: false)])
        expect(response.first! == vector(0), "worker protocol returns valid vectors with literal input")
        do {
            _ = try await client.embed([.init(value: "bad", isImage: false)])
            preconditionFailure("bad dimensions must fail")
        } catch ClipboardEmbeddingError.invalidReply { count += 1 }
        let started = Date()
        let request = Task { try await client.embed([.init(value: "slow", isImage: false)]) }
        try await Task.sleep(for: .milliseconds(200))
        request.cancel()
        do { _ = try await request.value; preconditionFailure("cancel must fail") }
        catch is CancellationError { expect(Date().timeIntervalSince(started) < 3, "cancellation terminates the helper promptly") }

        if CommandLine.arguments.count == 4 {
            try await realModel(helper: URL(fileURLWithPath: CommandLine.arguments[1]),
                models: URL(fileURLWithPath: CommandLine.arguments[2]), reference: URL(fileURLWithPath: CommandLine.arguments[3]))
            try await lifecycle(root: root.appendingPathComponent("Lifecycle"), helper: helper,
                models: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
        print("\(count) semantic clipboard checks passed")
    }

    static func until(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition() {
            precondition(Date() < deadline, "lifecycle operation timed out")
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    static func lifecycle(root: URL, helper: URL, models: URL) async throws {
        let suite = "com.spotter.semantic-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ClipboardStore(directory: root.appendingPathComponent("Clipboard"))
        let folder = root.appendingPathComponent("Semantic")
        let destination = folder.appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in ClipboardSemanticModels.files {
            try FileManager.default.linkItem(at: models.appendingPathComponent(file.name), to: destination.appendingPathComponent(file.name))
        }
        let manager = ClipboardSemanticSearch(store: store, directory: folder, defaults: defaults, executable: helper)
        store.onHistoryChanged = { manager.historyDidChange() }
        store.onItemRemoved = { manager.remove($0) }
        store.onHistoryCleared = { manager.clear() }
        manager.start()
        expect(!manager.isEnabled && manager.status == "Off", "fresh installs do not start the model")
        store.addText("fixture clipboard content", sourceBundleID: nil)
        let original = store.items[0].id
        manager.setEnabled(true)
        try await until { manager.status == "1 entries indexed" }
        manager.search("some meaning")
        try await until { !manager.isSearching }
        expect(store.search("some meaning").map(\.id) == [original], "manager publishes results from its persisted index")
        manager.search("obsolete request")
        manager.search("new request")
        try await until { !manager.isSearching }
        expect(store.search("obsolete request").isEmpty, "obsolete asynchronous queries are discarded")
        store.clearAll()
        store.addText("fresh content after clearing history", sourceBundleID: nil)
        let fresh = store.items[0].id
        try await until { manager.status == "1 entries indexed" }
        manager.search("new meaning")
        try await until { !manager.isSearching }
        expect(store.search("new meaning").map(\.id) == [fresh], "a new capture after clear is indexed without resurrecting old history")
        expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Index/\(original).plist").path), "clear deletes the old embedding file")
        manager.search("pending query")
        manager.setEnabled(false)
        try await until { !FileManager.default.fileExists(atPath: folder.path) }
        expect(store.search("new meaning").isEmpty && !manager.isSearching, "revoking consent immediately removes matches and cancels queries")
        expect(store.items.count == 1, "disabling semantic search preserves clipboard history")
        expect(!FileManager.default.fileExists(atPath: destination.path), "revoking consent removes model weights")
        store.onHistoryChanged = nil
        store.onItemRemoved = nil
        store.onHistoryCleared = nil

        let importedFolder = root.appendingPathComponent("Imported")
        let stagedHelper = root.appendingPathComponent("initially-missing-helper")
        let imported = ClipboardSemanticSearch(store: store, directory: importedFolder, defaults: defaults, executable: stagedHelper)
        imported.setEnabled(true)
        try await until { imported.error != nil && !imported.isPreparing }
        expect(imported.canImportModels, "failed setup offers a local model import")
        try FileManager.default.copyItem(at: helper, to: stagedHelper)
        let corrupt = root.appendingPathComponent("corrupt-models")
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try Data("not a model".utf8).write(to: corrupt.appendingPathComponent(ClipboardSemanticModels.files[0].name))
        imported.importModels(from: corrupt)
        try await until { imported.error != nil && !imported.isPreparing }
        expect(!FileManager.default.fileExists(atPath: importedFolder.appendingPathComponent("Models/\(ClipboardSemanticModels.files[0].name)").path), "corrupt imported weights are not installed")
        imported.importModels(from: models)
        try await until { imported.status == "1 entries indexed" }
        expect(imported.error == nil, "verified local weights work without a network request")
        imported.setEnabled(false)
        try await until { !FileManager.default.fileExists(atPath: importedFolder.path) }
        count += 1
    }

    static func realModel(helper: URL, models: URL, reference: URL) async throws {
        let client = ClipboardEmbeddingClient(executable: helper, models: models)
        let texts = ["The customer paid the outstanding bill by bank transfer yesterday.",
            "Bake the sourdough loaf in a hot oven for forty minutes.",
            "我们下周二讨论设计稿，地点是三楼会议室。"]
        let inputs = texts.map { ClipboardEmbeddingInput(value: ClipboardSemanticEngine.documents($0)[0], isImage: false) }
            + [ClipboardEmbeddingInput(value: reference.appendingPathComponent("screen.png").path, isImage: true),
               ClipboardEmbeddingInput(value: reference.appendingPathComponent("photo.jpg").path, isImage: true)]
        let vectors = try await client.embed(inputs)
        expect(vectors.allSatisfy { $0 != nil }, "real model embeds English, Chinese and images")
        let ids = inputs.map { _ in UUID() }
        let entries = zip(ids, vectors).map { ClipboardSemanticEntry(id: $0.0, fingerprint: "fixture", vectors: [$0.1!]) }
        let queries = [("settled invoice", 0), ("bread recipe", 1), ("设计评审在哪里开会", 2),
            ("a computer application window with a sidebar and a blue button", 3), ("绿色山丘、太阳和一棵树", 4)]
        let queryVectors = try await client.embed(queries.map {
            ClipboardEmbeddingInput(value: ClipboardSemanticEngine.query($0.0), isImage: false, isQuery: true)
        })
        for ((query, target), vector) in zip(queries, queryVectors) {
            let ranked = ClipboardSemanticEngine.ranked(query: vector!, entries: entries)
            print("real query '\(query)': expected rank \(ranked.firstIndex(of: ids[target]).map { String($0 + 1) } ?? "missing")")
            expect(ranked.first == ids[target], "real semantic retrieval: \(query)")
        }
    }
}
