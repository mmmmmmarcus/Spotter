import Foundation

/// A saved link with optional `{argument}` placeholders. Hand-written `Codable` so only `name` and
/// `link` are required — a hand-edited settings file stays loadable.
struct Quicklink: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var name: String
    /// The raw template, placeholders included.
    var link: String
    /// Bundle id of the app to open it with, or nil for the system default. The icon is that app's — a quicklink has no icon of its own.
    var openWithBundleID: String?
    /// A timestamp, not a flag: pinning orders by *when* it was pinned.
    var pinnedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(), name: String, link: String, openWithBundleID: String? = nil,
        pinnedAt: Date? = nil, createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.link = link
        self.openWithBundleID = openWithBundleID
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, link, openWithBundleID, pinnedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        link = try c.decode(String.self, forKey: .link)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        openWithBundleID = try? c.decode(String.self, forKey: .openWithBundleID)
        pinnedAt = try? c.decode(Date.self, forKey: .pinnedAt)
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    var isPinned: Bool { pinnedAt != nil }

    /// Pinned first (newest pin wins), then alphabetical — the single sort every surface uses.
    static func precedes(_ lhs: Quicklink, _ rhs: Quicklink) -> Bool {
        switch (lhs.pinnedAt, rhs.pinnedAt) {
        case let (l?, r?): return l > r
        case (.some, nil): return true
        case (nil, .some): return false
        default:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

/// What a link resolves to, which decides whether argument values get percent-encoded.
enum QuicklinkDestination: Equatable, Sendable {
    /// http/https — values are percent-encoded.
    case web
    /// A custom scheme (`raycast://`, `obsidian://`) — encoded like the web.
    case deeplink
    /// A filesystem path — never encoded; a path is not a URL.
    case file

    /// Read from the template, before substitution, so a value can't change the destination kind.
    static func detect(_ link: String) -> QuicklinkDestination {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix("file:") {
            return .file
        }
        guard let schemeEnd = trimmed.range(of: "://") else {
            // Bare `example.com/x` reads as web; that's what a user typing a domain means.
            return .web
        }
        let scheme = trimmed[..<schemeEnd.lowerBound].lowercased()
        return (scheme == "http" || scheme == "https") ? .web : .deeplink
    }

    var encodesValues: Bool { self != .file }
}

/// One `{argument}` in a template.
struct QuicklinkArgument: Equatable, Sendable {
    /// The token's declared name, or a generated one for a bare `{argument}`.
    let name: String
    /// Fixed choices from `options="a,b,c"`, offered as rows instead of free text.
    let options: [String]
    /// Where the token sits in the template, so substitution needs no re-parse.
    let range: Range<String.Index>
}

enum QuicklinkTemplate {
    /// Parses `{argument}`, `{argument name="City"}` and `{argument options="a,b"}` left to right.
    /// Unknown `{…}` content is left alone — a URL fragment with braces isn't an argument.
    static func arguments(in link: String) -> [QuicklinkArgument] {
        var result: [QuicklinkArgument] = []
        var index = link.startIndex
        var unnamed = 0
        while index < link.endIndex, let open = link[index...].firstIndex(of: "{") {
            guard let close = link[open...].firstIndex(of: "}") else { break }
            let body = String(link[link.index(after: open)..<close])
            index = link.index(after: close)
            guard body == "argument" || body.hasPrefix("argument ") else { continue }
            unnamed += 1
            let name = attribute("name", in: body) ?? "Argument \(unnamed)"
            let options = (attribute("options", in: body) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            result.append(
                QuicklinkArgument(name: name, options: options, range: open..<index))
        }
        return result
    }

    /// Replaces tokens right-to-left so earlier ranges stay valid.
    static func fill(
        _ link: String, values: [String], destination: QuicklinkDestination
    ) -> String {
        let tokens = arguments(in: link)
        var result = link
        for (offset, token) in tokens.enumerated().reversed() {
            let raw = offset < values.count ? values[offset] : ""
            let value = destination.encodesValues ? percentEncoded(raw) : raw
            result.replaceSubrange(token.range, with: value)
        }
        return result
    }

    /// `urlQueryAllowed` keeps `&`, `+` and `=` — the characters that would silently split a query.
    static func percentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func attribute(_ name: String, in body: String) -> String? {
        guard let key = body.range(of: name + "=\"") else { return nil }
        let rest = body[key.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }
}
