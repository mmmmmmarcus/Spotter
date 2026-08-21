import Foundation

@main
struct ScopesTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("spotter-scopes-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func makeDir(_ url: URL) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // A scope directory with two apps, a non-app sibling, a hidden app, a vendor folder one level down, and a bundle two levels down.
        let apps = root.appendingPathComponent("Apps")
        makeDir(apps.appendingPathComponent("Alpha.app"))
        makeDir(apps.appendingPathComponent("Beta.app"))
        makeDir(apps.appendingPathComponent("Notes.txt"))
        makeDir(apps.appendingPathComponent(".Hidden.app"))
        let nested = apps.appendingPathComponent("Sub")
        makeDir(nested.appendingPathComponent("Deep.app"))
        let deeper = nested.appendingPathComponent("Deeper")
        makeDir(deeper.appendingPathComponent("Buried.app"))
        // Helper bundles live inside a real app; the walk must treat `.app` as a leaf and never find this one.
        makeDir(
            apps.appendingPathComponent("Alpha.app").appendingPathComponent("Contents")
                .appendingPathComponent("Helper.app"))

        let found = SearchScopes.appBundles(in: [apps.path]).map(\.lastPathComponent)
        check(
            "direct .app children are indexed",
            Set(found).isSuperset(of: ["Alpha.app", "Beta.app"]))
        check("non-app children are skipped", !found.contains("Notes.txt"))
        check("hidden bundles are skipped", !found.contains(".Hidden.app"))
        check("one subfolder deep is indexed", found.contains("Deep.app"))
        // Bounded at one level: anything deeper is indexed by adding its folder as its own scope.
        check("two subfolders deep is not indexed", !found.contains("Buried.app"))
        check("a bundle's own tree is never opened", !found.contains("Helper.app"))
        check(
            "a nested folder works as its own scope",
            SearchScopes.appBundles(in: [deeper.path]).map(\.lastPathComponent) == ["Buried.app"])

        // A scope may be a single bundle rather than a directory — that's how Finder ships as a default.
        check(
            "an .app scope is indexed directly",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Alpha.app").path])
                .map(\.lastPathComponent) == ["Alpha.app"])
        check(
            "a missing .app scope yields nothing",
            SearchScopes.appBundles(in: [apps.appendingPathComponent("Gone.app").path]).isEmpty)
        check(
            "a missing directory scope is skipped without failing the rest",
            SearchScopes.appBundles(in: [root.appendingPathComponent("Nope").path, deeper.path])
                .map(\.lastPathComponent) == ["Buried.app"])

        check(
            "scopes are scanned in order",
            SearchScopes.appBundles(in: [deeper.path, apps.path]).map(\.lastPathComponent).first
                == "Buried.app")

        let home = fm.homeDirectoryForCurrentUser.path
        check(
            "expand resolves a tilde",
            SearchScopes.expand("~/Applications") == home + "/Applications")
        check(
            "abbreviate restores the tilde",
            SearchScopes.abbreviate(home + "/Applications") == "~/Applications")
        check(
            "tilde survives a round trip",
            SearchScopes.abbreviate(SearchScopes.expand("~/Applications")) == "~/Applications")
        check(
            "expand leaves an absolute path alone",
            SearchScopes.expand("/Applications") == "/Applications")
        check(
            "a trailing slash is trimmed",
            SearchScopes.abbreviate("/Applications/") == "/Applications")
        check("root survives trimming", SearchScopes.abbreviate("/") == "/")

        check(
            "normalize dedups after abbreviating",
            SearchScopes.normalize([
                "/Applications", "/Applications/", home + "/Applications", "~/Applications",
            ])
                == ["/Applications", "~/Applications"])
        check("normalize preserves order", SearchScopes.normalize(["/B", "/A"]) == ["/B", "/A"])
        check("normalize drops blanks", SearchScopes.normalize(["  ", "/A"]) == ["/A"])
        check(
            "defaults are already normalized",
            SearchScopes.normalize(SearchScopes.defaults) == SearchScopes.defaults)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
