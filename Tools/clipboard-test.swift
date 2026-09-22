// Standalone test for the clipboard store — compiles the *real* source (no copy to sync):
// swiftc -swift-version 6 Spotter/Plugins/Clipboard/ClipboardStore.swift Tools/clipboard-test.swift -o /tmp/clipboard-test && /tmp/clipboard-test
//
// Every store here is built on a throwaway directory under the system temp dir, so a run can never
// see or touch a real clipboard history.

import Foundation
import CoreGraphics

@main
@MainActor
struct ClipboardTests {
    static var failures = 0
    static var passes = 0

    static func main() async {
        shortcutMigration()
        quickPresentation()
        pinOrder()
        unpinRejoinsAsNewest()
        pasteLeavesPinsAlone()
        pinsSurvivePruningAndTheWindow()
        pinsLeadFilteredSearches()
        textFormClassification()
        typeFilterSplitsTheHistory()
        typeFilterJoinsTheSearchMemo()
        persistence()
        migrationFromShippedDatabase()
        await portableSnapshot()
        await incrementalSync()
        await imageSnapshotCache()
        await mappedImageLifetime()
        await namedImagesKeepTheirName()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func shortcutMigration() {
        let suite = "com.spotter.tests.clipboard-shortcut." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = "legacy", new = "quick"
        let binding = #"{"carbonKeyCode":6,"carbonModifiers":4352}"#
        func migrate(_ isDefault: Bool = true) {
            ClipboardShortcutMigration.apply(defaults: defaults, legacyKey: old, quickKey: new, legacyUsesDefault: isDefault)
        }
        defaults.set(binding, forKey: old)
        migrate()
        expect(defaults.string(forKey: new) == binding && defaults.object(forKey: old) == nil,
            "default clipboard chord transfers without duplicate ownership")
        defaults.removeObject(forKey: new)
        defaults.set(binding, forKey: old)
        migrate()
        expect(defaults.object(forKey: new) == nil && defaults.string(forKey: old) == binding,
            "subsequent explicit unbind or reassignment survives restart")
        defaults.removePersistentDomain(forName: suite)
        defaults.set(binding, forKey: old)
        defaults.set("custom quick binding", forKey: new)
        migrate()
        expect(defaults.string(forKey: new) == "custom quick binding" && defaults.string(forKey: old) == binding,
            "existing quick shortcut is not overwritten")
        defaults.removePersistentDomain(forName: suite)
        defaults.set("custom legacy binding", forKey: old)
        migrate(false)
        expect(defaults.string(forKey: old) == "custom legacy binding" && defaults.object(forKey: new) == nil,
            "custom full-history binding is not transferred")
        defaults.removePersistentDomain(forName: suite)
        migrate()
        expect(defaults.object(forKey: new) == nil && defaults.bool(forKey: ClipboardShortcutMigration.marker),
            "fresh install leaves default seeding to the shortcut registry")
    }

    static func quickPresentation() {
        let items = (0..<8).map { ClipboardItem(text: "Entry \($0)", sourceBundleID: nil) }
        for (value, title) in [("hello", "Text"), ("https://example.com", "Link"), ("123", "Number"), ("name@example.com", "Email")] {
            expect(ClipboardItem(text: value, sourceBundleID: nil).typeTitle == title, "details describe the classified content type")
        }
        expect(ClipboardItem(imagePath: "/tmp/image.png", sourceBundleID: nil).typeTitle == "Image", "image details keep their content type")
        expect(QuickClipboardPresentation.recentItems(items).map(\.id) == Array(items.prefix(5)).map(\.id),
            "quick history keeps the five newest entries in store order")
        expect(QuickClipboardPresentation.recentItems([]).isEmpty, "empty quick history stays empty")
        let multiline = ClipboardItem(text: "hello\n  world\t你好", sourceBundleID: nil)
        expect(QuickClipboardPresentation.title(for: multiline) == "hello world 你好", "preview collapses line breaks")
        let long = ClipboardItem(text: String(repeating: "👨‍👩‍👧‍👦", count: 170), sourceBundleID: nil)
        let preview = QuickClipboardPresentation.title(for: long)
        expect(preview.count == 161 && preview.hasSuffix("…"), "preview truncates at whole graphemes")
        expect(long.text?.count == 170, "preview never truncates the payload to paste")
        for (text, symbol) in [("Words", "textformat.alt"), ("https://example.com", "link"), ("123", "number.sign")] {
            expect(QuickClipboardPresentation.symbol(for: ClipboardItem(text: text, sourceBundleID: nil)) == symbol,
                "quick history reuses the \(symbol) classifier")
        }
        expect(QuickClipboardPresentation.symbol(for: ClipboardItem(imagePath: "/tmp/image.png", sourceBundleID: nil)) == "photo",
            "images retain their type symbol")
        let screen = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let right = QuickClipboardPresentation.frame(anchor: CGRect(x: -1000, y: 800, width: 0, height: 0), screen: screen, count: 5)
        expect(right.minX == -988, "picker opens to the pointer's right on a secondary screen")
        let left = QuickClipboardPresentation.frame(anchor: CGRect(x: -5, y: 800, width: 0, height: 0), screen: screen, count: 5)
        expect(left.maxX == -17, "picker flips left at the right edge")
        for pointer in [CGPoint(x: -1440, y: 100), CGPoint(x: -1, y: 1000), CGPoint(x: -900, y: 110)] {
            let frame = QuickClipboardPresentation.frame(anchor: CGRect(origin: pointer, size: .zero), screen: screen, count: 5)
            expect(screen.insetBy(dx: 8, dy: 8).contains(frame), "picker stays within the visible screen at \(pointer)")
        }
        let empty = QuickClipboardPresentation.frame(anchor: CGRect(x: -1000, y: 800, width: 0, height: 0), screen: screen, count: 0)
        expect(empty.height == QuickClipboardPresentation.rowHeight, "empty history uses one placeholder pill")
    }

    static func incrementalSync() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)
        let id = UUID()
        let now = Date()
        func image(_ data: Data) -> ClipboardSyncItem {
            ClipboardSyncItem(id: id, kind: .image, text: nil, imageData: data,
                imageExtension: "png", createdAt: now, sourceBundleID: nil, pinnedAt: now)
        }
        let original = image(Data(repeating: 7, count: 1024 * 1024))
        await store.replace(with: [original])
        let path = store.items[0].imagePath!
        let attributes = try! FileManager.default.attributesOfItem(atPath: path)
        let revision = store.syncRevision
        await store.replace(with: [original])
        expect(store.syncRevision == revision, "identical sync makes no SQLite writes")
        let text = ClipboardSyncItem(id: UUID(), kind: .text, text: "incoming newest", imageData: nil,
            imageExtension: nil, createdAt: now.addingTimeInterval(1), sourceBundleID: nil, pinnedAt: nil)
        await store.replace(with: [text, original])
        expect(store.items.map(\.id) == [text.id, id], "incremental sync keeps newest-first order")
        expect(store.syncRevision - revision < 20, "one incoming text does not rewrite existing history")
        let after = try! FileManager.default.attributesOfItem(atPath: path)
        expect(after[.systemFileNumber] as? UInt64 == attributes[.systemFileNumber] as? UInt64,
            "text sync preserves the image inode")
        expect(after[.modificationDate] as? Date == attributes[.modificationDate] as? Date,
            "text sync does not rewrite image bytes")
        let changed = image(Data(repeating: 8, count: 1024 * 1024))
        await store.replace(with: [text, changed])
        let changedPath = store.items.first { $0.id == id }!.imagePath!
        expect((try? Data(contentsOf: URL(fileURLWithPath: changedPath))) == changed.imageData,
            "changed image bytes with the same ID are applied")
        expect(!FileManager.default.fileExists(atPath: path), "superseded owned blob is removed")
        await store.replace(with: [text])
        expect(!FileManager.default.fileExists(atPath: changedPath), "remote deletion removes the owned blob")
        expect(store.items.map(\.id) == [text.id], "remote deletion remains authoritative")
        await store.replace(with: [])
        expect(store.items.isEmpty, "empty remote history clears local history")
        await store.replace(with: [text])
        let baseline = store.synchronizationBaseline()
        store.addText("copied during remote decoding", sourceBundleID: nil)
        store.remove(store.items.first { $0.id == text.id }!)
        await store.replace(with: [text], preservingChangesSince: baseline)
        expect(store.items.map(\.text) == ["copied during remote decoding"],
            "local copies and deletions made during sync survive the remote apply")
    }

    static func imageSnapshotCache() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("cached.png")
        try! Data([1, 2, 3]).write(to: file)
        let reads = ReadCount()
        let cache = ClipboardSyncImages(byteLimit: 4) { url in
            reads.increment()
            return try Data(contentsOf: url)
        }
        let item = ClipboardItem(imagePath: file.path, sourceBundleID: nil)
        _ = await cache.snapshot([item])
        _ = await cache.snapshot([ClipboardItem(text: "new text", sourceBundleID: nil), item])
        expect(reads.value == 1, "text changes reuse the cached image bytes")
        try! Data([3, 2, 1]).write(to: file, options: .atomic)
        let updated = await cache.snapshot([item])
        expect(reads.value == 2 && updated.first?.imageData == Data([3, 2, 1]),
            "atomic replacement invalidates even a same-size image")
        try! Data(repeating: 9, count: 5).write(to: file, options: .atomic)
        _ = await cache.snapshot([item])
        _ = await cache.snapshot([item])
        expect(reads.value == 4, "oversized images are not retained in the bounded cache")
        try! FileManager.default.removeItem(at: file)
        let missing = await cache.snapshot([item])
        expect(missing.isEmpty, "deleted blobs cannot be resurrected from the cache")
    }

    static func mappedImageLifetime() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let owned = dir.appendingPathComponent("owned", isDirectory: true)
        try! FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        let file = owned.appendingPathComponent("image.png")
        let oldBytes = Data(repeating: 7, count: 2 * 1024 * 1024)
        let newBytes = Data(repeating: 9, count: oldBytes.count)
        try! oldBytes.write(to: file, options: .atomic)
        let cache = ClipboardSyncImages(managedDirectory: owned)
        let row = ClipboardItem(imagePath: file.path, sourceBundleID: nil)
        let first = await cache.snapshot([row])
        try! newBytes.write(to: file, options: .atomic)
        let second = await cache.snapshot([row])
        try! FileManager.default.removeItem(at: file)
        expect(first.first?.imageData == oldBytes, "mapped snapshot survives atomic replacement and deletion")
        expect(second.first?.imageData == newBytes, "new snapshot maps the replacement inode")
        let missing = await cache.snapshot([row])
        expect(missing.isEmpty, "unlinked mappings never restore deleted history")

        let external = dir.appendingPathComponent("external.png")
        try! oldBytes.write(to: external)
        let externalRow = ClipboardItem(imagePath: external.path, sourceBundleID: nil)
        let externalSnapshot = await cache.snapshot([externalRow])
        let linked = owned.appendingPathComponent("linked.png")
        try! FileManager.default.createSymbolicLink(at: linked, withDestinationURL: external)
        let linkedSnapshot = await cache.snapshot([ClipboardItem(imagePath: linked.path, sourceBundleID: nil)])
        let handle = try! FileHandle(forWritingTo: external)
        try! handle.truncate(atOffset: 0)
        try! handle.close()
        expect(externalSnapshot.first?.imageData == oldBytes, "external snapshot owns its bytes after truncation")
        expect(linkedSnapshot.first?.imageData == oldBytes, "symlink inside managed directory must not map external bytes")
    }

    final class ReadCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func increment() { lock.withLock { count += 1 } }
    }

    // MARK: - Cases

    /// A screenshot's whole identity is its file name, so the name it is given has to reach disk —
    /// and two captures inside the same minute must not land on one path.
    static func namedImagesKeepTheirName() async {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ClipboardStore(directory: dir)
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        store.addImage(png, named: "Claude_SpotterScreenshot_2608041812", sourceBundleID: nil)
        store.addImage(png, named: "Claude_SpotterScreenshot_2608041812", sourceBundleID: nil)
        store.addImage(png, sourceBundleID: nil)
        try? await Task.sleep(for: .milliseconds(400))

        let images = store.items.filter { $0.kind == .image }
        let names = Set(images.compactMap { ($0.imagePath as NSString?)?.lastPathComponent })
        expect(images.count == 3, "every image was recorded")
        expect(
            names.contains("Claude_SpotterScreenshot_2608041812.png"),
            "a named capture keeps its name on disk")
        expect(
            names.contains("Claude_SpotterScreenshot_2608041812-2.png"),
            "a second capture in the same minute takes the next stem")
        expect(
            images.filter(\.isScreenshot).count == 2,
            "both captures read back as screenshots, the unnamed image does not")
        expect(
            names.allSatisfy { FileManager.default.fileExists(atPath: dir.path + "/images/" + $0) },
            "each row points at a file that exists")
    }

    /// Pins stack in pin order, oldest pin first, regardless of how old the entries are.
    static func pinOrder() {
        withStore { store, _ in
            store.addText("oldest", sourceBundleID: nil)
            store.addText("middle", sourceBundleID: nil)
            store.addText("newest", sourceBundleID: nil)

            store.togglePinned(item(store, "oldest"))
            expect(texts(store) == ["oldest", "newest", "middle"], "first pin leads the list")

            store.togglePinned(item(store, "middle"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "second pin joins below the first, and does not sort by recency")

            store.togglePinned(item(store, "newest"))
            expect(
                texts(store) == ["oldest", "middle", "newest"],
                "pins hold pin order, not the recency order they had in the history")
        }
    }

    /// Unpinning drops the row in as today's newest entry rather than back where it came from.
    static func unpinRejoinsAsNewest() {
        withStore { store, _ in
            store.addText("a", sourceBundleID: nil)
            store.addText("b", sourceBundleID: nil)
            store.addText("c", sourceBundleID: nil)
            let before = item(store, "a").createdAt

            store.togglePinned(item(store, "a"))
            store.togglePinned(item(store, "a"))

            expect(texts(store) == ["a", "c", "b"], "unpinned row leads the history")
            expect(!item(store, "a").isPinned, "pin stamp cleared")
            expect(item(store, "a").createdAt > before, "unpin re-recencies the row")
        }
    }

    /// Pasting a pinned entry must not reshuffle the Pinned section.
    static func pasteLeavesPinsAlone() {
        withStore { store, _ in
            store.addText("one", sourceBundleID: nil)
            store.addText("two", sourceBundleID: nil)
            store.togglePinned(item(store, "one"))
            store.togglePinned(item(store, "two"))
            let stamp = item(store, "one").createdAt

            store.promote(item(store, "one"))

            expect(texts(store) == ["one", "two"], "promote leaves a pinned row in place")
            expect(item(store, "one").createdAt == stamp, "promote does not rewrite a pinned row")

            store.addText("three", sourceBundleID: nil)
            store.addText("four", sourceBundleID: nil)
            store.promote(item(store, "three"))
            expect(
                texts(store) == ["one", "two", "three", "four"],
                "an unpinned row still promotes to the head of the history")
        }
    }

    /// Retention sweeps everything around a pin but never the pin itself.
    static func pinsSurvivePruningAndTheWindow() {
        withStore { store, dir in
            // Older than the 1-day retention the case sets below, but inside the default the import prunes against.
            let old = Date().addingTimeInterval(-2 * 86_400)
            _ = store.importEntries([
                entry("ancient-pinned", at: old),
                entry("ancient-loose", at: old.addingTimeInterval(1)),
                entry("fresh", at: Date()),
            ])
            store.togglePinned(item(store, "ancient-pinned"))

            store.maxAge = 86_400
            store.enforceLimits()
            expect(
                Set(texts(store)) == ["ancient-pinned", "fresh"],
                "pruning skips pinned rows and takes the rest")

            // Reopen: the pin must come back even though it is far outside the retention window.
            let reopened = ClipboardStore(directory: dir)
            reopened.maxAge = 86_400
            reopened.load()
            expect(
                Set(texts(reopened)) == ["ancient-pinned", "fresh"],
                "a pin outlives retention across a relaunch")
        }
    }

    /// A pin must lead a filtered search even when the FTS statement's LIMIT cannot reach it.
    static func pinsLeadFilteredSearches() {
        withStore { store, _ in
            var seed: [ClipboardItem] = []
            let base = Date().addingTimeInterval(-10_000)
            // The pinned hit is the oldest of 260 matches; the FTS statement stops at 200.
            seed.append(entry("needle in the haystack", at: base))
            for i in 1...259 {
                seed.append(entry("haystack filler \(i)", at: base.addingTimeInterval(Double(i))))
            }
            _ = store.importEntries(seed)
            store.togglePinned(item(store, "needle in the haystack"))

            let results = store.search("haystack")
            expect(results.count > 200, "FTS results plus the pinned block")
            expect(
                results.first?.text == "needle in the haystack",
                "the pinned match leads the filtered results")
            expect(
                results.filter(\.isPinned).count == 1, "the pinned row is not duplicated")

            let short = store.search("ne")  // below the trigram threshold: the fallback path
            expect(
                short.first?.text == "needle in the haystack",
                "the pinned match leads the fallback search too")
        }
    }

    /// The classifier is a heuristic, so what must *not* read as a link matters as much as what must.
    static func textFormClassification() {
        func form(_ text: String) -> ClipboardItem.TextForm? {
            ClipboardItem(text: text, sourceBundleID: nil).textForm
        }

        for link in [
            "https://example.com/a?b=c", "http://localhost:3000", "vscode://file/tmp/x",
            "www.apple.com", "github.com/anthropics", "spotter.dev",
        ] {
            expect(form(link) == .link, "\(link) is a link")
        }
        for address in ["marcus@example.com", "mailto:marcus@example.com", "a.b-c@sub.domain.co"] {
            expect(form(address) == .email, "\(address) is an email")
        }
        // Filenames are domain-shaped; the lower-case rule and the TLD list are what keep them out.
        for plain in [
            "report.pdf", "index.html", "App.swift", "Safari.app", "script.sh", "Apple.com",
            "@apple.com", "two@at@signs.com", "just some copied prose", "",
        ] {
            expect(form(plain) == .plain, "\(plain.isEmpty ? "(empty)" : plain) is plain text")
        }

        for number in ["42", "-12.5", "+0.5", ".75", "1,234.56", "1e-6", "12%", "１２３", " 42\n"] {
            expect(form(number) == .number, "\(number) is a complete number")
        }
        for plain in ["50080C", "FFC700", "1.2.3", "12,34", "42 apples", "1 + 2", "NaN", "Infinity"] {
            expect(form(plain) == .plain, "\(plain) is not a complete number")
        }
        expect(form("https://example.com/42")?.systemImage == "link", "URL rows use link")
        expect(form("42")?.systemImage == "number.sign", "numeric rows use number.sign")
        expect(form("some text")?.systemImage == "textformat.alt", "text rows use textformat.alt")
        withStore { store, _ in
            store.addText("123", sourceBundleID: nil)
            store.addText("hello", sourceBundleID: nil)
            expect(store.search("", filter: .number).map(\.text) == ["123"], "numbers filter selects numeric entries")
            expect(store.search("", filter: .text).map(\.text) == ["hello"], "text filter excludes numbers")
            expect(store.search("", filter: .all).count == 2, "switching filters preserves all entries")
        }

        let long = String(repeating: "a", count: 2050) + ".com"
        expect(form(long) == .plain, "past the detection limit everything is prose")

        let image = ClipboardItem(imagePath: "/tmp/x.png", sourceBundleID: nil)
        expect(image.textForm == nil, "an image has no text form")
    }

    /// Each filter returns only its own type, and filtering after the pinned split keeps a matching pin at the head of its block.
    static func typeFilterSplitsTheHistory() {
        withStore { store, _ in
            _ = store.importEntries([
                entry("plain prose", at: Date().addingTimeInterval(-40)),
                entry("https://example.com/one", at: Date().addingTimeInterval(-30)),
                entry("marcus@example.com", at: Date().addingTimeInterval(-20)),
                entry("https://example.com/two", at: Date().addingTimeInterval(-10)),
            ])

            expect(
                store.search("", filter: .all).count == 4, "All Types is the whole history")
            expect(
                store.search("", filter: .text).compactMap(\.text) == ["plain prose"],
                "Text Only excludes links and addresses")
            expect(
                store.search("", filter: .link).count == 2, "Links Only keeps both links")
            expect(
                store.search("", filter: .email).compactMap(\.text) == ["marcus@example.com"],
                "Emails Only keeps the address")
            expect(store.search("", filter: .image).isEmpty, "no images were captured")

            // A screenshot is an image with a name Spotter wrote; nothing is stored to say so.
            let capture = ClipboardItem(
                imagePath: "/tmp/images/Claude_SpotterScreenshot_2608041812.png",
                sourceBundleID: nil)
            let pasted = ClipboardItem(imagePath: "/tmp/images/IMG_4021.png", sourceBundleID: nil)
            expect(capture.isScreenshot, "a Spotter capture reads as a screenshot")
            expect(!pasted.isScreenshot, "an image copied from elsewhere does not")
            expect(
                ClipboardFilter.screenshot.matches(capture)
                    && !ClipboardFilter.screenshot.matches(pasted),
                "Screenshots Only keeps captures and drops other images")
            expect(
                ClipboardFilter.image.matches(capture),
                "a screenshot is still an image, so Images Only keeps it")
            expect(
                !ClipboardFilter.screenshot.matches(entry("prose", at: Date())),
                "text is never a screenshot")

            store.togglePinned(item(store, "https://example.com/one"))
            expect(
                store.search("", filter: .link).first?.text == "https://example.com/one",
                "a pinned link still leads its block under a filter")
        }
    }

    /// The filter moves without the query moving, so a query-only memo key would serve the previous filter's rows.
    static func typeFilterJoinsTheSearchMemo() {
        withStore { store, _ in
            _ = store.importEntries([
                entry("example plain text", at: Date().addingTimeInterval(-20)),
                entry("https://example.com/deep", at: Date().addingTimeInterval(-10)),
            ])

            let all = store.search("example", filter: .all)
            let links = store.search("example", filter: .link)
            let text = store.search("example", filter: .text)
            expect(all.count == 2, "the unfiltered query matches both")
            expect(links.compactMap(\.text) == ["https://example.com/deep"], "same query, links")
            expect(text.compactMap(\.text) == ["example plain text"], "same query, text")
            expect(
                store.search("example", filter: .all).count == 2,
                "returning to All Types does not serve the filtered memo")
        }
    }

    /// Pin stamps and their order survive a reopen.
    static func persistence() {
        withStore { store, dir in
            store.addText("first", sourceBundleID: nil)
            store.addText("second", sourceBundleID: nil)
            store.addText("third", sourceBundleID: nil)
            store.togglePinned(item(store, "third"))
            store.togglePinned(item(store, "first"))

            let reopened = ClipboardStore(directory: dir)
            reopened.load()
            expect(
                texts(reopened) == ["third", "first", "second"],
                "pin order is restored from disk, not recomputed from recency")

            reopened.togglePinned(item(reopened, "third"))
            expect(texts(reopened) == ["first", "third", "second"], "unpin after a reload")

            reopened.clearAll()
            expect(reopened.items.isEmpty, "Clear History takes pins too")
        }
    }

    /// A shipped pre-pin database migrates in place. Failing to open one is not a soft failure: the store deletes and recreates a database it can't open, taking the history with it.
    static func migrationFromShippedDatabase() {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("clipboard.sqlite3")
        seedPrePinDatabase(at: db)

        let store = ClipboardStore(directory: dir)
        store.load()
        expect(texts(store) == ["newer", "older"], "existing history survives the migration")

        store.addText("after", sourceBundleID: nil)
        store.togglePinned(item(store, "older"))
        expect(texts(store) == ["older", "after", "newer"], "the migrated database takes pins")

        let reopened = ClipboardStore(directory: dir)
        reopened.load()
        expect(texts(reopened) == ["older", "after", "newer"], "and keeps them across a reopen")

        expect(
            sqlite(db, "SELECT name FROM pragma_table_info('items')").contains("pinned_at"),
            "the pin stamp column was added")
        expect(
            sqlite(db, "SELECT name FROM sqlite_master WHERE type = 'index'")
                .contains("items_pinned_at"),
            "and indexed")
    }

    /// Sync snapshots carry image bytes, not an absolute cache path from the source Mac.
    static func portableSnapshot() async {
        let sourceDir = scratchDirectory()
        let destinationDir = scratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destinationDir)
        }
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let sourceImage = sourceDir.appendingPathComponent("source.png")
        try? imageData.write(to: sourceImage)
        let source = ClipboardStore(directory: sourceDir)
        let now = Date()
        _ = source.importEntries([
            entry("portable text", at: now.addingTimeInterval(-1)),
            ClipboardItem(
                id: UUID(), kind: .image, text: nil, imagePath: sourceImage.path,
                createdAt: now, sourceBundleID: "test.source",
                pinnedAt: now),
        ])

        let snapshot = await source.syncSnapshot()
        let destination = ClipboardStore(directory: destinationDir)
        await destination.replace(with: snapshot)
        expect(texts(destination).contains("portable text"), "sync restores clipboard text")
        guard let image = destination.items.first(where: { $0.kind == .image }),
            let restoredURL = destination.imageURL(for: image)
        else {
            fail("sync restores clipboard image row")
            return
        }
        expect(restoredURL.path.hasPrefix(destinationDir.path), "sync rewrites image paths locally")
        expect((try? Data(contentsOf: restoredURL)) == imageData, "sync restores clipboard image bytes")
        expect(image.isPinned, "sync restores clipboard pin state")
    }

    // MARK: - Harness

    /// Runs `body` against a store rooted in a fresh temp directory, torn down afterwards.
    static func withStore(_ body: (ClipboardStore, URL) -> Void) {
        let dir = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        body(ClipboardStore(directory: dir), dir)
    }

    static func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "spotter-clipboard-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes the schema as shipped before pinning existed: no `pinned_at`, and two rows to migrate.
    static func seedPrePinDatabase(at url: URL) {
        let now = Date().timeIntervalSince1970
        sqlite(
            url,
            """
            CREATE TABLE items(
              id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, text TEXT, image_path TEXT,
              created_at REAL NOT NULL, source_app TEXT
            );
            CREATE INDEX items_created_at ON items(created_at);
            CREATE VIRTUAL TABLE items_fts USING fts5(
              text, content='items', content_rowid='rowid', tokenize='trigram'
            );
            CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
              INSERT INTO items_fts(rowid, text) VALUES(new.rowid, new.text);
            END;
            CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
              INSERT INTO items_fts(items_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            END;
            INSERT INTO items(id, kind, text, created_at)
              VALUES('\(UUID().uuidString)', 'text', 'older', \(now - 60));
            INSERT INTO items(id, kind, text, created_at)
              VALUES('\(UUID().uuidString)', 'text', 'newer', \(now));
            """)
    }

    /// Rows returned by the `sqlite3` CLI — used to write a legacy database and to read the schema back, neither of which the store exposes.
    @discardableResult
    static func sqlite(_ database: URL, _ sql: String) -> Set<String> {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        task.arguments = [database.path, sql]
        task.standardOutput = pipe
        guard (try? task.run()) != nil else {
            fail("could not run sqlite3")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 { fail("sqlite3 failed: \(sql.prefix(60))") }
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
    }

    static func entry(_ text: String, at date: Date) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: date,
            sourceBundleID: nil)
    }

    static func texts(_ store: ClipboardStore) -> [String] {
        store.search("").compactMap(\.text)
    }

    static func item(_ store: ClipboardStore, _ text: String) -> ClipboardItem {
        guard let match = store.items.first(where: { $0.text == text }) else {
            fail("no entry named \(text)")
            exit(1)
        }
        return match
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
