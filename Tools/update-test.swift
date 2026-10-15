// Compile: swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift Spotter/Core/UpdatePresentation.swift Tools/update-test.swift -o /tmp/update-test && /tmp/update-test
import Foundation

@main
struct UpdateTests {
    static func main() {
        var failures = 0

        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        func v(_ raw: String) -> SemanticVersion {
            guard let version = SemanticVersion(raw) else {
                failures += 1
                print("FAIL  could not parse version \(raw)")
                return SemanticVersion("0.0.0")!
            }
            return version
        }

        // Parsing
        check("parses plain version", v("0.5.7") == v("0.5.7"))
        check("strips v prefix", v("v1.2.3") == v("1.2.3"))
        check("ignores build metadata", v("1.2.3+42") == v("1.2.3"))
        check("keeps prerelease ids", v("1.2.3-beta.4").prerelease == ["beta", "4"])
        check("rejects two-part versions", SemanticVersion("1.2") == nil)
        check("rejects junk", SemanticVersion("release-one") == nil)

        // Ordering
        check("patch orders numerically", v("0.5.7") < v("0.5.10"))
        check("minor beats patch", v("0.5.10") < v("0.6.0"))
        check("prerelease precedes release", v("1.0.0-beta.1") < v("1.0.0"))
        check("numeric prerelease ids order numerically", v("1.0.0-beta.2") < v("1.0.0-beta.10"))
        check("numeric ids order below alphanumeric", v("1.0.0-1") < v("1.0.0-alpha"))
        check("shorter prerelease precedes longer", v("1.0.0-beta") < v("1.0.0-beta.1"))

        func manifest(_ version: String, channel: String = "stable", zip: String? = nil) -> Data {
            let base = "https://github.com/mmmmmmarcus/Spotter/releases"
            return try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "channel": channel,
                "releases": [["version": version, "releaseURL": "\(base)/tag/v\(version)",
                    "zipURL": zip ?? "\(base)/download/v\(version)/Spotter-\(version).zip",
                    "dmgURL": "\(base)/download/v\(version)/Spotter-\(version).dmg",
                    "releaseNotes": "  - A fix.  "]]])
        }
        let feed = manifest("0.6.0")
        let stable = try? UpdateFeed.latest(in: feed, channel: .stable)
        check("static feed decodes version", stable?.version == v("0.6.0"))
        check("static feed preserves release notes", stable?.releaseNotes == "- A fix.")
        check("static feed carries complete ZIP URL", stable?.zipAssetURL?.lastPathComponent == "Spotter-0.6.0.zip")
        check("wrong channel is rejected", (try? UpdateFeed.latest(in: feed, channel: .beta)) == nil)
        check("stable rejects prerelease", (try? UpdateFeed.latest(in: manifest("0.7.0-beta.1"), channel: .stable)) == nil)
        check("beta decodes beta", (try? UpdateFeed.latest(in: manifest("0.7.0-beta.1", channel: "beta"), channel: .beta))?.version == v("0.7.0-beta.1"))
        for url in ["http://github.com/mmmmmmarcus/Spotter/releases/download/v0.6.0/Spotter-0.6.0.zip",
                    "https://example.com/malware.zip",
                    "https://github.com/mmmmmmarcus/Spotter/releases/download/v0.5.0/Spotter-0.5.0.zip"] {
            check("rejects insecure, foreign or wrong-version assets", (try? UpdateFeed.latest(in: manifest("0.6.0", zip: url), channel: .stable)) == nil)
        }
        check("schema change fails explicitly", (try? UpdateFeed.latest(in: Data("{\"schemaVersion\":2,\"channel\":\"stable\",\"releases\":[]}".utf8), channel: .stable)) == nil)
        check("empty beta feed is valid", (try? UpdateFeed.latest(in: Data("{\"schemaVersion\":1,\"channel\":\"beta\",\"releases\":[]}".utf8), channel: .beta)) == nil)
        check("malformed JSON is rejected", (try? UpdateFeed.latest(in: Data("junk".utf8), channel: .stable)) == nil)
        check("feed host is static Pages", UpdateFeed.url(for: .stable).host == "mmmmmmarcus.github.io")
        check("feed endpoints are channel-isolated", UpdateFeed.url(for: .stable) != UpdateFeed.url(for: .beta))
        let pageFallback = UpdateRelease(version: v("0.9.0"), pageURL: stable!.pageURL, zipAssetURL: nil, releaseNotes: "")

        let release = stable!
        let idle = UpdatePresentation(status: .idle, release: nil, progress: nil)
        check("no upgrade row without a known release", idle.actions == [.check])
        let available = UpdatePresentation(status: .available(release), release: release, progress: nil)
        check("available update replaces the single check action", available.actions == [.upgrade])
        check("Return installs without moving selection", available.primaryTitle(at: 0) == "Install Update")
        check("selected upgrade offers installation", available.primaryTitle(at: 0) == "Install Update")
        check("new update retains selection zero", available.selection(after: idle.actions, index: 0) == 0)
        check("removed upgrade clamps selection to check", idle.selection(after: available.actions, index: 1) == 0)
        let manual = UpdatePresentation(status: .available(pageFallback), release: pageFallback, progress: nil)
        check("DMG-only action opens release", manual.primaryTitle(at: 0) == "View Release")
        for status: UpdateStatus in [.checking, .installing] {
            let busy = UpdatePresentation(status: status, release: release, progress: .downloading(nil))
            check("busy work keeps a single row", busy.actions.count == 1)
            check("busy work cannot double-start a check or install", busy.primaryTitle(at: 0) == nil && busy.primaryTitle(at: 1) == nil)
        }
        let failed = UpdatePresentation(status: .failed("Download failed"), release: release, progress: nil)
        check("failure retains retryable upgrade", failed.actions == available.actions && failed.primaryTitle(at: 0) == "Install Update")
        check("failure stays visible in the check row", failed.checkDetail == "Download failed")
        let current = UpdatePresentation(status: .upToDate, release: nil, progress: nil)
        check("latest version has one inactive status row", current.actions.count == 1 && current.primaryTitle(at: 0) == nil)
        check("latest version status is the row title", current.title == "You’re on the latest version")
        check("checking has its own title", UpdatePresentation(status: .checking, release: release, progress: nil).title == "Checking…")
        check("available row shows version transition", available.detail(currentVersion: "1.0.0") == "1.0.0 → \(release.version.description)")
        check("byte fraction is measured", UpdateInstallProgress.download(written: 25, expected: 100).fraction == 0.25)
        check("unknown content length never invents a percentage", UpdateInstallProgress.download(written: 25, expected: -1).fraction == nil)
        check("zero content length remains indeterminate", UpdateInstallProgress.download(written: 25, expected: 0).fraction == nil)
        check("byte fraction stays bounded", UpdateInstallProgress.download(written: 150, expected: 100).fraction == 1)
        let partial = UpdateInstallProgress.downloading(0.5)
        check("late byte callbacks cannot move progress backward", !partial.accepts(.downloading(0.2)))
        check("unknown-length callback cannot erase measured progress", !partial.accepts(.downloading(nil)))
        check("invalid fractions are rejected", !partial.accepts(.downloading(.nan)) && !partial.accepts(.downloading(2)))
        let stages: [UpdateInstallProgress] = [.downloading(nil), .unpacking, .verifying, .installing, .relaunching]
        for (current, next) in zip(stages, stages.dropFirst()) {
            check("real completion advances to the next stage", current.accepts(next))
            check("late callbacks cannot regress an installation stage", !next.accepts(current))
        }
        check("installation stages never pretend to have byte percentages", stages.dropFirst().allSatisfy { $0.fraction == nil })
        check("download and installation have distinct labels", stages[0].title != stages[3].title)

        print(failures == 0 ? "\nUpdate feed: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
