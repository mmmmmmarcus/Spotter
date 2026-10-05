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

        // Selection
        let feed = """
        [
          {"id": 123, "tag_name": "v0.7.0-beta.2", "prerelease": true, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v0.7.0-beta.2",
           "assets": [{"name": "Spotter-0.7.0-beta.2.zip",
                       "browser_download_url": "https://example.com/beta.zip"}]},
          {"id": 123, "tag_name": "v0.6.0", "prerelease": false, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v0.6.0",
           "body": "  ## Improvements\\n\\n- **Faster** clipboard search.  ",
           "assets": [{"name": "Spotter-0.6.0.dmg",
                       "browser_download_url": "https://example.com/stable.dmg"},
                      {"name": "Spotter-0.6.0.zip",
                       "browser_download_url": "https://example.com/stable.zip"}]},
          {"id": 123, "tag_name": "v0.8.0", "prerelease": false, "draft": true,
           "html_url": "https://github.com/x/y/releases/tag/v0.8.0",
           "assets": []},
          {"id": 123, "tag_name": "v0.5.0", "prerelease": false, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v0.5.0",
           "assets": []}
        ]
        """.data(using: .utf8)!

        let stable = UpdateFeed.latestUpdate(in: feed, channel: .stable, current: v("0.5.0"))
        check("stable picks the newest full release", stable?.version == v("0.6.0"))
        check("stable skips prereleases and drafts", stable?.tag == "v0.6.0")
        check("stable finds the zip asset", stable?.zipAssetURL?.absoluteString == "https://example.com/stable.zip")
        check("release notes preserve Markdown and trim surrounding whitespace",
            stable?.releaseNotes == "## Improvements\n\n- **Faster** clipboard search.")
        let decoded = try! JSONDecoder().decode([UpdateFeed.GitHubRelease].self, from: feed)
        check("latest release notes remain available when already up to date",
            UpdateFeed.latest(from: decoded, channel: .stable) == stable)

        let beta = UpdateFeed.latestUpdate(in: feed, channel: .beta, current: v("0.6.0"))
        check("beta accepts prereleases", beta?.version == v("0.7.0-beta.2"))
        check("legacy releases without a body remain usable", beta?.releaseNotes == "")
        check("latest notes remain channel-isolated", UpdateFeed.latest(from: decoded, channel: .beta) == beta)
        check("empty feeds have no notes to display", UpdateFeed.latest(from: [], channel: .stable) == nil)

        check(
            "up to date returns nil",
            UpdateFeed.latestUpdate(in: feed, channel: .stable, current: v("0.6.0")) == nil)
        check(
            "current prerelease updates to its release",
            UpdateFeed.latestUpdate(in: feed, channel: .beta, current: v("0.6.0-beta.9"))?.version
                == v("0.7.0-beta.2"))

        let mixedChannels = """
        [
          {"id": 123, "tag_name": "v1.1.0", "prerelease": false, "draft": false,
           "html_url": "https://github.com/x/y/releases/tag/v1.1.0",
           "assets": [{"name": "Spotter-1.1.0.zip",
                       "browser_download_url": "https://example.com/stable-1.1.zip"}]},
          {"id": 123, "tag_name": "v1.0.0-beta.8", "prerelease": true, "draft": false,
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
        [{"id": 123, "tag_name": "v0.9.0", "prerelease": false, "draft": false,
          "html_url": "https://github.com/x/y/releases/tag/v0.9.0",
          "body": "- Fixes clipboard navigation.",
          "assets": [{"name": "Spotter-0.9.0.dmg",
                      "browser_download_url": "https://example.com/only.dmg"}]}]
        """.data(using: .utf8)!
        let pageFallback = UpdateFeed.latestUpdate(in: dmgOnly, channel: .stable, current: v("0.5.0"))
        check("dmg-only release still reports, without a zip asset", pageFallback != nil && pageFallback?.zipAssetURL == nil)
        for body in ["null", "\"\"", "\"   \""] {
            let emptyNotes = String(decoding: dmgOnly, as: UTF8.self)
                .replacingOccurrences(of: "\"- Fixes clipboard navigation.\"", with: body)
            check("null or blank notes keep the release available",
                UpdateFeed.latestUpdate(in: Data(emptyNotes.utf8), channel: .stable, current: v("0.5.0"))?.releaseNotes == "")
        }

        check("malformed feed returns nil", UpdateFeed.latestUpdate(in: Data("junk".utf8), channel: .stable, current: v("0.1.0")) == nil)

        let recoveredAssets = """
        [{"name":"Spotter-0.9.0.zip", "browser_download_url":"https://example.com/recovered.zip"}]
        """.data(using: .utf8)!
        let recovered = try? UpdateFeed.resolvingAssets(recoveredAssets, for: pageFallback!)
        check("missing list ZIP is recovered from dedicated assets response", recovered?.zipAssetURL?.lastPathComponent == "recovered.zip")
        check("recovery preserves release identity", recovered?.id == pageFallback?.id && recovered?.version == pageFallback?.version && recovered?.pageURL == pageFallback?.pageURL)
        check("dedicated asset recovery preserves release notes", recovered?.releaseNotes == "- Fixes clipboard navigation.")
        let unrelatedAssets = """
        [{"name":"Spotter-1.0.0.zip", "browser_download_url":"https://example.com/wrong.zip"}]
        """.data(using: .utf8)!
        check("recovery refuses another version's ZIP", (try? UpdateFeed.resolvingAssets(unrelatedAssets, for: pageFallback!))?.zipAssetURL == nil)
        check("confirmed empty asset list retains manual fallback", (try? UpdateFeed.resolvingAssets(Data("[]".utf8), for: pageFallback!)) == pageFallback)
        check("malformed assets fail rather than becoming a manual-only release", (try? UpdateFeed.resolvingAssets(Data("junk".utf8), for: pageFallback!)) == nil)

        let release = stable!
        let idle = UpdatePresentation(status: .idle, release: nil, progress: nil)
        check("no upgrade row without a known release", idle.actions == [.check])
        let available = UpdatePresentation(status: .available(release), release: release, progress: nil)
        check("upgrade precedes check when available", available.actions == [.upgrade, .check])
        check("Return follows selected check instead of installing", available.primaryTitle(at: 1) == "Check for Updates")
        check("selected upgrade offers installation", available.primaryTitle(at: 0) == "Install Update")
        check("new upgrade row preserves selected check", available.selection(after: idle.actions, index: 0) == 1)
        check("removed upgrade clamps selection to check", idle.selection(after: available.actions, index: 1) == 0)
        let manual = UpdatePresentation(status: .available(pageFallback!), release: pageFallback, progress: nil)
        check("DMG-only action opens release", manual.primaryTitle(at: 0) == "View Release")
        for status: UpdateStatus in [.checking, .installing] {
            let busy = UpdatePresentation(status: status, release: release, progress: .downloading(nil))
            check("busy work keeps both row identities", busy.actions == available.actions)
            check("busy work cannot double-start a check or install", busy.primaryTitle(at: 0) == nil && busy.primaryTitle(at: 1) == nil)
        }
        let failed = UpdatePresentation(status: .failed("Download failed"), release: release, progress: nil)
        check("failure retains retryable upgrade", failed.actions == available.actions && failed.primaryTitle(at: 0) == "Install Update")
        check("failure stays visible in the check row", failed.checkDetail == "Download failed")
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
