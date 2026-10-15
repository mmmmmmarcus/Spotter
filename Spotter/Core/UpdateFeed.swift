import Foundation

// Pure version ordering and static-feed decoding; networking and installation belong to UpdateStore.
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

enum UpdateChannel: String, Sendable {
    case stable
    case beta
}

// One published release reduced to what the updater needs.
struct UpdateRelease: Equatable, Sendable {
    let version: SemanticVersion
    let pageURL: URL
    /// The in-app-installable asset; nil means the release only carries a DMG and the UI falls back to opening `pageURL`.
    let zipAssetURL: URL?
    let releaseNotes: String
}

enum UpdateFeed {
    enum InvalidFeed: Error { case schema, channel, release }

    private struct Manifest: Decodable {
        let schemaVersion: Int
        let channel: String
        let releases: [Release]
    }

    private struct Release: Decodable {
        let version: String
        let releaseURL: URL
        let zipURL: URL
        let dmgURL: URL
        let releaseNotes: String
    }

    static func url(for channel: UpdateChannel) -> URL {
        URL(string: "https://mmmmmmarcus.github.io/Spotter/updates/\(channel.rawValue).json")!
    }

    static func latest(in data: Data, channel: UpdateChannel) throws -> UpdateRelease? {
        let feed = try JSONDecoder().decode(Manifest.self, from: data)
        guard feed.schemaVersion == 1 else { throw InvalidFeed.schema }
        guard feed.channel == channel.rawValue else { throw InvalidFeed.channel }
        let releases = try feed.releases.map { entry -> UpdateRelease in
            guard let version = SemanticVersion(entry.version), version.description == entry.version,
                  (channel == .stable) == version.prerelease.isEmpty else { throw InvalidFeed.release }
            let base = "https://github.com/mmmmmmarcus/Spotter/releases"
            guard entry.releaseURL.absoluteString == "\(base)/tag/v\(version)",
                  entry.zipURL.absoluteString == "\(base)/download/v\(version)/Spotter-\(version).zip",
                  entry.dmgURL.absoluteString == "\(base)/download/v\(version)/Spotter-\(version).dmg"
            else { throw InvalidFeed.release }
            return UpdateRelease(version: version, pageURL: entry.releaseURL,
                zipAssetURL: entry.zipURL, releaseNotes: entry.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return releases.max { $0.version < $1.version }
    }
}
