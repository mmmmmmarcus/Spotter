import Foundation

/// Pure update-feed logic: semver parsing/ordering, GitHub release decoding and channel-aware
/// selection. Foundation-only so `Tools/update-test.swift` compiles the real sources; the network,
/// filesystem and installer live in `UpdateStore`.
struct SemanticVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// Dot-separated prerelease identifiers (`["beta", "3"]`); empty means a full release.
    let prerelease: [String]

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Build metadata never participates in ordering.
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        let dash = s.firstIndex(of: "-")
        let core = dash.map { String(s[..<$0]) } ?? s
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
            major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = dash.map { s[s.index(after: $0)...].split(separator: ".").map(String.init) } ?? []
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        // Same core: a prerelease precedes its release (0.6.0-beta.1 < 0.6.0).
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x < y
            // Numeric identifiers order below alphanumeric ones (semver §11).
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }
}

enum UpdateChannel: Sendable {
    case stable
    case beta
}

/// One GitHub release reduced to what the updater needs.
struct UpdateRelease: Equatable, Sendable {
    let version: SemanticVersion
    let tag: String
    let pageURL: URL
    /// The in-app-installable asset; nil means the release only carries a DMG and the UI falls back to opening `pageURL`.
    let zipAssetURL: URL?
}

enum UpdateFeed {
    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let prerelease: Bool
        let draft: Bool
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease
            case draft
            case htmlURL = "html_url"
            case assets
        }
    }

    /// Decodes a GitHub releases-list response and returns the newest release that is strictly newer than `current` for the channel, or nil when up to date. Stable ignores prereleases; beta takes both, so a beta user still lands on a newer stable.
    static func latestUpdate(
        in data: Data, channel: UpdateChannel, current: SemanticVersion
    ) -> UpdateRelease? {
        guard let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) else {
            return nil
        }
        return select(from: releases, channel: channel, current: current)
    }

    static func select(
        from releases: [GitHubRelease], channel: UpdateChannel, current: SemanticVersion
    ) -> UpdateRelease? {
        let candidates: [(GitHubRelease, SemanticVersion)] = releases.compactMap { release in
            guard !release.draft else { return nil }
            if channel == .stable, release.prerelease { return nil }
            guard let version = SemanticVersion(release.tagName) else { return nil }
            return (release, version)
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }), best.1 > current else { return nil }
        return UpdateRelease(
            version: best.1,
            tag: best.0.tagName,
            pageURL: best.0.htmlURL,
            zipAssetURL: best.0.assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadURL)
    }
}
