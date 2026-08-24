import Foundation

/// The clipboard list's type filter. Foundation-only and pure so it compiles into `Tools/clipboard-test.swift` beside `ClipboardStore`.
enum ClipboardFilter: String, CaseIterable, Sendable {
    case all
    case text
    case image
    case screenshot
    case link
    case email

    var title: String {
        switch self {
        case .all: return "All Types"
        case .text: return "Text Only"
        case .image: return "Images Only"
        case .screenshot: return "Screenshots Only"
        case .link: return "Links Only"
        case .email: return "Emails Only"
        }
    }

    /// Also the header button's glyph, so the bar states the active filter without opening the menu.
    var systemImage: String {
        switch self {
        case .all: return "line.3.horizontal.decrease"
        case .text: return "textformat"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .link: return "link"
        case .email: return "at"
        }
    }

    /// What the empty list says, so a filter hiding every entry never reads as an empty history.
    var emptyMessage: String {
        switch self {
        case .all: return "Clipboard history is empty"
        case .text: return "No text in clipboard history"
        case .image: return "No images in clipboard history"
        case .screenshot: return "No screenshots in clipboard history"
        case .link: return "No links in clipboard history"
        case .email: return "No email addresses in clipboard history"
        }
    }

    /// The text kinds are exclusive: a copied URL is a link, not a narrower kind of text.
    /// Screenshots are the one deliberate subset — a Spotter capture is an image, and an image
    /// filter that hid the images Spotter itself took would simply be wrong.
    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .image: return item.kind == .image
        case .screenshot: return item.isScreenshot
        case .text: return item.textForm == .plain
        case .link: return item.textForm == .link
        case .email: return item.textForm == .email
        }
    }

    /// Identity for `.all`, so an unfiltered list never pays for a copy.
    func apply(to items: [ClipboardItem]) -> [ClipboardItem] {
        self == .all ? items : items.filter(matches)
    }
}

extension ClipboardItem {
    /// Read off the file name rather than a stored column, the same way `textForm` is derived:
    /// Spotter names its own captures, so the name is the marker, and improving the rule stays a
    /// code change instead of a column, a migration and a backfill.
    var isScreenshot: Bool {
        guard kind == .image, let imagePath else { return false }
        return ScreenshotFileName.isScreenshot(fileName: (imagePath as NSString).lastPathComponent)
    }

    /// What a text entry holds. `Kind` says how an entry is stored; this says what it is.
    enum TextForm: Sendable {
        case plain
        case link
        case email
    }

    /// Derived on demand and never stored, so improving the classifier stays a code change instead of a column, a migration and a backfill.
    var textForm: TextForm? {
        guard kind == .text, let text else { return nil }
        return Self.classify(text)
    }

    /// A link or an address is one short token, so anything longer is prose by definition.
    private static let detectionLimit = 2048

    /// A scheme-less link needs a TLD people actually copy, or every `report.pdf` reads as one.
    private static let commonTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "co", "ai", "app", "dev", "me", "info", "biz",
        "xyz", "tv", "ly", "gg", "to", "uk", "us", "eu", "de", "fr", "es", "it", "nl", "se", "no",
        "fi", "dk", "ch", "at", "be", "ie", "cz", "ru", "ua", "tr", "cn", "jp", "kr", "hk", "sg",
        "au", "nz", "ca", "mx", "br", "ar", "za",
    ]

    /// Guarded cheapest-first: the whole list reclassifies on every render, so the common case (a paragraph of prose) must cost one length check.
    private static func classify(_ text: String) -> TextForm {
        // `utf8.count` is O(1); `count` would walk graphemes across a multi-megabyte copy.
        guard text.utf8.count <= detectionLimit else { return .plain }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isWhitespace) else { return .plain }
        if let form = schemeForm(of: token) { return form }
        if isAddress(token) { return .email }
        return isBareDomain(token) ? .link : .plain
    }

    /// `mailto:` is an address; any other `scheme://` is a link, so `vscode://` needs no allowlist.
    private static func schemeForm(of token: String) -> TextForm? {
        if token.range(of: "mailto:", options: [.caseInsensitive, .anchored]) != nil {
            return .email
        }
        guard let separator = token.range(of: "://") else { return nil }
        let scheme = token[token.startIndex..<separator.lowerBound]
        guard !scheme.isEmpty,
            scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "+" || $0 == "-" || $0 == ".") })
        else { return nil }
        return .link
    }

    /// `local@domain.tld`: one `@`, a non-empty local part, and a host-shaped domain.
    private static func isAddress(_ token: String) -> Bool {
        let parts = token.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return topLevelLabel(of: parts[1]) != nil
    }

    /// The one judgement call, since `report.pdf` and `index.html` are domain-shaped too. Worst case files a row under the wrong type.
    private static func isBareDomain(_ token: String) -> Bool {
        let host = token.prefix { !"/?#:".contains($0) }
        if host.range(of: "www.", options: [.caseInsensitive, .anchored]) != nil { return true }
        // Hosts are canonically lower case, which is what keeps `Safari.app` out of the links.
        guard !host.contains(where: \.isUppercase), let tld = topLevelLabel(of: host) else {
            return false
        }
        return commonTopLevelDomains.contains(String(tld))
    }

    /// The last label of a host, or nil unless every label is one — which is what stops an address-shaped token like `@apple.com` from also reading as a bare domain.
    private static func topLevelLabel(of host: Substring) -> Substring? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy(isHostLabel), let tld = labels.last,
            tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        return tld
    }

    private static func isHostLabel(_ label: Substring) -> Bool {
        !label.isEmpty
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
