import Foundation

@main
struct QuicklinkTests {
    static func main() {
        var failures = 0

        func check<T: Equatable>(_ message: String, _ expected: T, _ actual: T) {
            if expected == actual {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message): expected \(expected), got \(actual)")
            }
        }

        // MARK: Destination detection

        check("https is web", .web, QuicklinkDestination.detect("https://example.com"))
        check("bare domain is web", .web, QuicklinkDestination.detect("example.com/search"))
        check(
            "custom scheme is a deeplink", .deeplink,
            QuicklinkDestination.detect("obsidian://open?vault=Notes"))
        check(
            "custom scheme does not require slashes", .deeplink,
            QuicklinkDestination.detect("mailto:hello@example.com"))
        check(
            "another slashless app scheme is a deeplink", .deeplink,
            QuicklinkDestination.detect("things:show?id=today"))
        check(
            "localhost with a port stays web", .web,
            QuicklinkDestination.detect("localhost:8080/path"))
        check(
            "a bare domain with a port stays web", .web,
            QuicklinkDestination.detect("example.com:8443/path"))
        check("absolute path is a file", .file, QuicklinkDestination.detect("/Users/me/Docs"))
        check("tilde path is a file", .file, QuicklinkDestination.detect("~/Downloads"))
        check("file url is a file", .file, QuicklinkDestination.detect("file:///tmp"))
        check("uppercase scheme still web", .web, QuicklinkDestination.detect("HTTPS://a.com"))
        check("files never encode", false, QuicklinkDestination.file.encodesValues)
        check("deeplinks encode", true, QuicklinkDestination.deeplink.encodesValues)

        // MARK: Argument parsing

        check("no arguments", 0, QuicklinkTemplate.arguments(in: "https://example.com").count)
        let bare = QuicklinkTemplate.arguments(in: "https://x.com/{argument}")
        check("one bare argument", 1, bare.count)
        check("bare argument is auto-named", "Argument 1", bare.first?.name ?? "")
        check("bare argument has no options", 0, bare.first?.options.count ?? -1)

        let named = QuicklinkTemplate.arguments(
            in: "https://wx.com/{argument name=\"City\"}/{argument name=\"Day\"}")
        check("two named arguments", 2, named.count)
        check("first name", "City", named.first?.name ?? "")
        check("second name", "Day", named.last?.name ?? "")

        let options = QuicklinkTemplate.arguments(
            in: "x://y/{argument name=\"Range\" options=\"day, week ,month\"}")
        check("options parsed", ["day", "week", "month"], options.first?.options ?? [])
        check("named alongside options", "Range", options.first?.name ?? "")

        check(
            "non-argument braces are ignored", 0,
            QuicklinkTemplate.arguments(in: "https://x.com/#{anchor}").count)
        check(
            "unterminated brace stops the scan", 0,
            QuicklinkTemplate.arguments(in: "https://x.com/{argument").count)
        check(
            "argument prefix is not a match", 0,
            QuicklinkTemplate.arguments(in: "https://x.com/{arguments}").count)
        check(
            "mixed braces still find the argument", 1,
            QuicklinkTemplate.arguments(in: "https://x.com/{skip}/{argument}").count)

        // MARK: Filling

        check(
            "single substitution", "https://x.com/swift",
            QuicklinkTemplate.fill(
                "https://x.com/{argument}", values: ["swift"], destination: .web))
        check(
            "spaces are encoded for the web", "https://x.com/hello%20world",
            QuicklinkTemplate.fill(
                "https://x.com/{argument}", values: ["hello world"], destination: .web))
        check(
            "query separators are encoded", "https://x.com?q=a%26b%3Dc",
            QuicklinkTemplate.fill(
                "https://x.com?q={argument}", values: ["a&b=c"], destination: .web))
        check(
            "plus is encoded so it can't read as a space", "https://x.com?q=a%2Bb",
            QuicklinkTemplate.fill(
                "https://x.com?q={argument}", values: ["a+b"], destination: .web))
        check(
            "file paths keep spaces verbatim", "~/My Docs/report card.pdf",
            QuicklinkTemplate.fill(
                "~/My Docs/{argument}", values: ["report card.pdf"], destination: .file))
        check(
            "two arguments fill left to right", "x://a/one/two",
            QuicklinkTemplate.fill(
                "x://a/{argument}/{argument}", values: ["one", "two"], destination: .deeplink))
        check(
            "a longer replacement does not shift the next token", "x://a/aaaaaaaa/b",
            QuicklinkTemplate.fill(
                "x://a/{argument}/{argument}", values: ["aaaaaaaa", "b"], destination: .deeplink))
        check(
            "missing values collapse to empty", "https://x.com//",
            QuicklinkTemplate.fill(
                "https://x.com/{argument}/{argument}", values: ["", ""], destination: .web))
        check(
            "extra values are ignored", "https://x.com/a",
            QuicklinkTemplate.fill(
                "https://x.com/{argument}", values: ["a", "b"], destination: .web))
        check(
            "named tokens are replaced whole", "https://wx.com/Tokyo",
            QuicklinkTemplate.fill(
                "https://wx.com/{argument name=\"City\"}", values: ["Tokyo"], destination: .web))
        check(
            "unicode survives encoding", "https://x.com/%E6%9D%B1%E4%BA%AC",
            QuicklinkTemplate.fill(
                "https://x.com/{argument}", values: ["東京"], destination: .web))

        // MARK: Sort order

        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 2_000)
        let unpinnedA = Quicklink(name: "Alpha", link: "https://a.com")
        let unpinnedB = Quicklink(name: "beta", link: "https://b.com")
        let pinnedOld = Quicklink(name: "Zulu", link: "https://z.com", pinnedAt: old)
        let pinnedNew = Quicklink(name: "Yankee", link: "https://y.com", pinnedAt: recent)

        check("pinned beats unpinned", true, Quicklink.precedes(pinnedOld, unpinnedA))
        check("unpinned never beats pinned", false, Quicklink.precedes(unpinnedA, pinnedOld))
        check("newer pin wins", true, Quicklink.precedes(pinnedNew, pinnedOld))
        check(
            "unpinned sort is case-insensitive", true, Quicklink.precedes(unpinnedA, unpinnedB))

        // MARK: Decoding tolerance

        let minimal = #"{"name":"Docs","link":"https://docs.example"}"#
        let decoded = try? JSONDecoder().decode(Quicklink.self, from: Data(minimal.utf8))
        check("minimal json decodes", "Docs", decoded?.name ?? "")
        check("missing pin decodes as unpinned", false, decoded?.isPinned ?? true)

        let missingLink = #"{"name":"Docs"}"#
        let broken = try? JSONDecoder().decode(Quicklink.self, from: Data(missingLink.utf8))
        check("a link is required", true, broken == nil)

        // MARK: Store round-trip

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quicklink-test-\(ProcessInfo.processInfo.processIdentifier).json")
        defer { try? FileManager.default.removeItem(at: url) }

        MainActor.assumeIsolated {
            let store = QuicklinkStore(fileURL: url)
            check("store starts empty", 0, store.quicklinks.count)

            var changes = 0
            store.onChange = { changes += 1 }
            store.add(unpinnedB)
            store.add(unpinnedA)
            check("add persists both", 2, store.quicklinks.count)
            check("add notifies", 2, changes)
            check("sorted alphabetically", "Alpha", store.sorted.first?.name ?? "")

            store.togglePinned(id: unpinnedB.id)
            check("pinning lifts to the top", "beta", store.sorted.first?.name ?? "")
            check("pin is recorded", true, store.quicklink(id: unpinnedB.id)?.isPinned ?? false)

            var edited = unpinnedA
            edited.name = "Alpha Renamed"
            store.update(edited)
            check("update keeps the count", 2, store.quicklinks.count)
            check(
                "update applies", "Alpha Renamed", store.quicklink(id: unpinnedA.id)?.name ?? "")

            let reloaded = QuicklinkStore(fileURL: url)
            check("reload restores both", 2, reloaded.quicklinks.count)
            check("reload restores the pin", "beta", reloaded.sorted.first?.name ?? "")

            reloaded.delete(id: unpinnedA.id)
            check("delete removes one", 1, reloaded.quicklinks.count)

            reloaded.replace(with: [
                unpinnedA, Quicklink(name: "  ", link: "https://blank.example"),
                Quicklink(name: "No Link", link: " "),
            ])
            check("replace drops unusable rows", 1, reloaded.quicklinks.count)
            check("replace keeps the good row", "Alpha", reloaded.quicklinks.first?.name ?? "")
        }

        // MARK: Launcher-entry identity

        // The entry id is what a per-quicklink global shortcut, favorite and alias are all keyed by,
        // so the round trip has to hold — a one-way id would strand every binding on the next launch.
        let identified = Quicklink(name: "Docs", link: "https://example.com")
        check(
            "the entry id carries the uuid", Quicklink.id(fromEntryID: identified.entryID),
            identified.id)
        check(
            "the entry id keeps its prefix", true,
            identified.entryID.hasPrefix(Quicklink.entryIDPrefix))
        check("a custom-command entry id is not a quicklink", nil,
            Quicklink.id(fromEntryID: "custom-command:" + UUID().uuidString.lowercased()))
        check("a built-in command id is not a quicklink", nil,
            Quicklink.id(fromEntryID: "command:calculator-history"))
        check("a malformed uuid resolves to nothing", nil,
            Quicklink.id(fromEntryID: Quicklink.entryIDPrefix + "not-a-uuid"))

        print(failures == 0 ? "\nAll quicklink tests passed." : "\n\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
