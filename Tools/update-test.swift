// Compile: swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift Tools/update-test.swift -o /tmp/update-test && /tmp/update-test
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

        // Selection
        let feed = """
        [
          {"tag_name": "v0.7.0-beta.2", "prerelease": true, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v0.7.0-beta.2",
           "assets": [{"name": "Spotter-0.7.0-beta.2.zip",
                       "browser_download_url": "https://example.com/beta.zip"}]},
          {"tag_name": "v0.6.0", "prerelease": false, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v0.6.0",
           "assets": [{"name": "Spotter-0.6.0.dmg",
                       "browser_download_url": "https://example.com/stable.dmg"},
                      {"name": "Spotter-0.6.0.zip",
                       "browser_download_url": "https://example.com/stable.zip"}]},
          {"tag_name": "v0.8.0", "prerelease": false, "draft": true,
           "html_url": "https://github.com/x/y/releases/tag/v0.8.0",
           "assets": []},
          {"tag_name": "v0.5.0", "prerelease": false, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v0.5.0",
           "assets": []}
        ]
        """.data(using: .utf8)!

        let stable = UpdateFeed.latestUpdate(in: feed, channel: .stable, current: v("0.5.0"))
        check("stable picks the newest full release", stable?.version == v("0.6.0"))
        check("stable skips prereleases and drafts", stable?.tag == "v0.6.0")
        check("stable finds the zip asset", stable?.zipAssetURL?.absoluteString == "https://example.com/stable.zip")

        let beta = UpdateFeed.latestUpdate(in: feed, channel: .beta, current: v("0.6.0"))
        check("beta accepts prereleases", beta?.version == v("0.7.0-beta.2"))

        check(
            "up to date returns nil",
            UpdateFeed.latestUpdate(in: feed, channel: .stable, current: v("0.6.0")) == nil)
        check(
            "current prerelease updates to its release",
            UpdateFeed.latestUpdate(in: feed, channel: .beta, current: v("0.6.0-beta.9"))?.version
                == v("0.7.0-beta.2"))

        let mixedChannels = """
        [
          {"tag_name": "v1.1.0", "prerelease": false, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v1.1.0",
           "assets": [{"name": "Spotter-1.1.0.zip",
                       "browser_download_url": "https://example.com/stable-1.1.zip"}]},
          {"tag_name": "v1.0.0-beta.8", "prerelease": true, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v1.0.0-beta.8",
           "assets": [{"name": "Spotter-1.0.0-beta.8.zip",
                       "browser_download_url": "https://example.com/beta-1.0.zip"}]}
        ]
        """.data(using: .utf8)!
        check(
            "beta ignores newer stable releases with a different bundle identity",
            UpdateFeed.latestUpdate(
                in: mixedChannels, channel: .beta, current: v("0.9.0-beta.1"))?.version
                == v("1.0.0-beta.8"))
        check(
            "stable ignores beta releases",
            UpdateFeed.latestUpdate(in: mixedChannels, channel: .stable, current: v("1.0.0"))?.version
                == v("1.1.0"))

        let dmgOnly = """
        [{"tag_name": "v0.9.0", "prerelease": false, "draft": false,
          "html_url": "https://github.com/x/y/releases/tag/v0.9.0",
          "assets": [{"name": "Spotter-0.9.0.dmg",
                      "browser_download_url": "https://example.com/only.dmg"}]}]
        """.data(using: .utf8)!
        let pageFallback = UpdateFeed.latestUpdate(in: dmgOnly, channel: .stable, current: v("0.5.0"))
        check("dmg-only release still reports, without a zip asset", pageFallback != nil && pageFallback?.zipAssetURL == nil)

        check("malformed feed returns nil", UpdateFeed.latestUpdate(in: Data("junk".utf8), channel: .stable, current: v("0.1.0")) == nil)

        print(failures == 0 ? "\nUpdate feed: ALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
