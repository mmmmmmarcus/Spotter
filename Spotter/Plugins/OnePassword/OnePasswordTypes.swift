import Foundation

/// One 1Password item as listed by `op item list` — metadata only, never a secret.
struct OnePasswordItem: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let category: String
    let vaultID: String
    let vaultName: String
    let isFavorite: Bool
    let username: String?
    let websiteURL: String?
}

/// One field of an opened item, as returned by `op item get`. `value` may be a secret — it lives
/// only in the manager's in-memory detail and is dropped when the view closes.
struct OnePasswordFieldItem: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let type: String
    let purpose: String?
    let value: String
    let sectionLabel: String?

    /// Rendered masked until explicitly revealed; copies stay concealed either way.
    var isConcealed: Bool { type == "CONCEALED" || type == "OTP" }
    var isOneTimePassword: Bool { type == "OTP" }
    var isNotes: Bool { purpose == "NOTES" }

    var symbol: String {
        switch purpose {
        case "USERNAME": return "person"
        case "PASSWORD": return "key"
        case "NOTES": return "note.text"
        default: break
        }
        switch type {
        case "OTP": return "timer"
        case "URL": return "link"
        case "EMAIL": return "envelope"
        case "PHONE": return "phone"
        case "DATE", "MONTH_YEAR": return "calendar"
        case "CONCEALED": return "asterisk"
        default: return "textformat"
        }
    }
}

/// Everything the in-palette item view renders for one opened item.
struct OnePasswordItemDetail: Equatable, Sendable {
    let item: OnePasswordItem
    let fields: [OnePasswordFieldItem]
    let websites: [String]
}

/// The per-item actions Spotter offers, mirroring the 1Password 8 action set.
enum OnePasswordItemAction: String, CaseIterable, Sendable {
    case view = "view-item"
    case openInApp = "open-in-1password"
    case openInBrowser = "open-in-browser"
    case copyUsername = "copy-username"
    case copyPassword = "copy-password"
    case copyOneTimePassword = "copy-one-time-password"
    case pasteUsername = "paste-username"
    case pastePassword = "paste-password"
    case pasteOneTimePassword = "paste-one-time-password"

    var title: String {
        switch self {
        case .view: "View Item"
        case .openInApp: "Open in 1Password"
        case .openInBrowser: "Open in Browser"
        case .copyUsername: "Copy Username"
        case .copyPassword: "Copy Password"
        case .copyOneTimePassword: "Copy One-Time Password"
        case .pasteUsername: "Paste Username"
        case .pastePassword: "Paste Password"
        case .pasteOneTimePassword: "Paste One-Time Password"
        }
    }

    var systemImage: String {
        switch self {
        case .view: "eye"
        case .openInApp: "arrow.up.forward.app"
        case .openInBrowser: "safari"
        case .copyUsername, .copyPassword, .copyOneTimePassword: "doc.on.doc"
        case .pasteUsername, .pastePassword, .pasteOneTimePassword: "text.insert"
        }
    }

    var isPaste: Bool {
        switch self {
        case .pasteUsername, .pastePassword, .pasteOneTimePassword: true
        default: false
        }
    }

    /// The concealed field the action reveals, as an `op read` field name; nil for open actions.
    var field: String? {
        switch self {
        case .copyUsername, .pasteUsername: "username"
        case .copyPassword, .pastePassword: "password"
        case .copyOneTimePassword, .pasteOneTimePassword: nil
        case .view, .openInApp, .openInBrowser: nil
        }
    }

    var isOneTimePassword: Bool {
        self == .copyOneTimePassword || self == .pasteOneTimePassword
    }

    /// What each category can do: every category views and opens, logins add everything, passwords
    /// everything but username.
    static func available(forCategory category: String) -> [OnePasswordItemAction] {
        switch category {
        case "LOGIN":
            return allCases
        case "PASSWORD":
            return allCases.filter { $0 != .copyUsername && $0 != .pasteUsername }
        default:
            return [.view, .openInApp]
        }
    }

    /// The ↵ action for an item: the user's preferred action when the category supports it, else View Item.
    static func primary(preferred: OnePasswordItemAction, category: String) -> OnePasswordItemAction {
        let available = available(forCategory: category)
        return available.contains(preferred) ? preferred : .view
    }
}

/// Category presentation: an SF Symbol and a readable label per `op` category string.
enum OnePasswordCategory {
    private static let symbols: [String: String] = [
        "API_CREDENTIAL": "chevron.left.forwardslash.chevron.right",
        "BANK_ACCOUNT": "building.columns",
        "CREDIT_CARD": "creditcard",
        "CRYPTO_WALLET": "bitcoinsign.circle",
        "CUSTOM": "archivebox",
        "DATABASE": "cylinder.split.1x2",
        "DOCUMENT": "doc",
        "DRIVER_LICENSE": "car",
        "EMAIL_ACCOUNT": "envelope",
        "IDENTITY": "person.text.rectangle",
        "LOGIN": "person.badge.key",
        "MEDICAL_RECORD": "cross.case",
        "MEMBERSHIP": "star.circle",
        "OUTDOOR_LICENSE": "leaf",
        "PASSPORT": "globe",
        "PASSWORD": "key",
        "REWARD_PROGRAM": "gift",
        "SECURE_NOTE": "note.text",
        "SERVER": "server.rack",
        "SOCIAL_SECURITY_NUMBER": "shield",
        "SOFTWARE_LICENSE": "doc.badge.gearshape",
        "SSH_KEY": "terminal",
        "WIRELESS_ROUTER": "wifi.router",
    ]

    static func symbol(for category: String) -> String {
        symbols[category] ?? "key"
    }

    static func label(for category: String) -> String {
        category.split(separator: "_")
            .map { $0.prefix(1) + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

/// Builds every `op` invocation and 1Password URL Spotter uses; nothing here executes anything.
enum OnePasswordCLI {
    /// Homebrew on Apple silicon, then the pkg installer's location.
    static let searchPaths = ["/opt/homebrew/bin/op", "/usr/local/bin/op"]

    /// Deliberately without `--long`: the plain listing already carries usernames and URLs, and the
    /// per-item field detail `--long` adds trips `op`'s internal 30-second desktop-app timeout on
    /// vaults around a thousand items.
    static var listItemsArguments: [String] {
        ["item", "list", "--format=json"]
    }

    static var accountArguments: [String] {
        ["account", "get", "--format=json"]
    }

    /// Secret reference read — ids come from `op` itself, so they are URL-safe by construction.
    static func readArguments(vaultID: String, itemID: String, field: String) -> [String] {
        ["read", "op://\(vaultID)/\(itemID)/\(field)"]
    }

    /// One-time passwords resolve by OTP type, not field name, so they go through `item get --otp`.
    static func oneTimePasswordArguments(itemID: String, vaultID: String) -> [String] {
        ["item", "get", itemID, "--vault", vaultID, "--otp"]
    }

    /// The full item for the in-palette view; the JSON includes concealed field values.
    static func itemDetailArguments(itemID: String, vaultID: String) -> [String] {
        ["item", "get", itemID, "--vault", vaultID, "--format=json"]
    }

    /// `op` has no standalone generator; a dry-run item create returns a password without saving anything.
    static func generatePasswordArguments(length: Int, digits: Bool, symbols: Bool) -> [String] {
        var recipe = ["letters"]
        if digits { recipe.append("digits") }
        if symbols { recipe.append("symbols") }
        recipe.append(String(length))
        return [
            "item", "create", "--dry-run", "--category", "Password",
            "--generate-password=" + recipe.joined(separator: ","), "--format=json",
        ]
    }

    static func viewItemURL(accountID: String?, vaultID: String, itemID: String) -> String {
        let account = accountID.map { "a=\($0)&" } ?? ""
        return "onepassword://view-item/?\(account)v=\(vaultID)&i=\(itemID)"
    }
}

/// Decodes `op --format=json` output and classifies its stderr. Pure — the harness feeds it fixtures.
enum OnePasswordParser {
    private struct RawItem: Decodable {
        struct RawVault: Decodable {
            let id: String
            let name: String?
        }
        struct RawURL: Decodable {
            let href: String
            let primary: Bool?
        }
        let id: String
        let title: String?
        let category: String?
        let favorite: Bool?
        let vault: RawVault
        let additionalInformation: String?
        let urls: [RawURL]?

        enum CodingKeys: String, CodingKey {
            case id, title, category, favorite, vault, urls
            case additionalInformation = "additional_information"
        }
    }

    private struct RawAccount: Decodable {
        let id: String
    }

    private struct RawDetailField: Decodable {
        struct RawSection: Decodable {
            let id: String?
            let label: String?
        }
        let id: String
        let type: String?
        let purpose: String?
        let label: String?
        let value: String?
        let totp: String?
        let section: RawSection?
    }

    private struct RawDetailItem: Decodable {
        let fields: [RawDetailField]?
    }

    private struct RawGeneratedItem: Decodable {
        struct RawField: Decodable {
            let id: String
            let value: String?
        }
        let fields: [RawField]?
    }

    /// Favorites first, then title, mirroring what 1Password's own list leads with.
    static func parseItems(_ data: Data) -> [OnePasswordItem]? {
        guard let raw = try? JSONDecoder().decode([RawItem].self, from: data) else { return nil }
        return raw.map { item in
            // `additional_information` is the username for logins; other categories reuse it for dates and previews.
            let info = item.additionalInformation?.trimmingCharacters(in: .whitespaces)
            let username = (item.category == "LOGIN" && info?.isEmpty == false && info != "—")
                ? info : nil
            let urls = item.urls ?? []
            return OnePasswordItem(
                id: item.id,
                title: item.title ?? "Untitled",
                category: item.category ?? "LOGIN",
                vaultID: item.vault.id,
                vaultName: item.vault.name ?? "",
                isFavorite: item.favorite ?? false,
                username: username,
                websiteURL: urls.first { $0.primary == true }?.href ?? urls.first?.href)
        }
        .sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func parseAccountID(_ data: Data) -> String? {
        (try? JSONDecoder().decode(RawAccount.self, from: data))?.id
    }

    /// The in-palette view for one item: its non-empty fields in `op`'s order (1Password's own),
    /// plus its websites. The summary rides along re-parsed so the view is self-contained.
    static func parseItemDetail(_ data: Data) -> OnePasswordItemDetail? {
        guard let items = parseItems(Data("[".utf8) + data + Data("]".utf8)),
            let item = items.first,
            let raw = try? JSONDecoder().decode(RawDetailItem.self, from: data)
        else { return nil }
        let fields = (raw.fields ?? []).compactMap { field -> OnePasswordFieldItem? in
            // An OTP field's current code arrives in `totp`; everything else in `value`. An OTP
            // field keeps its row even with nothing held — the copy action re-fetches via `--otp`.
            let isOTP = field.type == "OTP"
            let value = (isOTP ? (field.totp ?? field.value) : field.value) ?? ""
            guard isOTP || !value.isEmpty else { return nil }
            return OnePasswordFieldItem(
                id: field.id,
                label: field.label ?? field.id,
                type: field.type ?? "STRING",
                purpose: field.purpose,
                value: value,
                sectionLabel: field.section?.label)
        }
        let websites = (try? JSONDecoder().decode(RawItem.self, from: data))
            .map { ($0.urls ?? []).map(\.href) } ?? []
        return OnePasswordItemDetail(item: item, fields: fields, websites: websites)
    }

    static func parseGeneratedPassword(_ data: Data) -> String? {
        let item = try? JSONDecoder().decode(RawGeneratedItem.self, from: data)
        let value = item?.fields?.first { $0.id == "password" }?.value
        return value?.isEmpty == false ? value : nil
    }

    /// `op` prefixes each stderr line with `[ERROR] yyyy/MM/dd HH:mm:ss `; strip that and keep the guidance.
    static func errorMessage(fromStderr stderr: String) -> String {
        let pattern = #"\[\w+\]\s+\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+"#
        let stripped = stderr.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? "1Password CLI reported an error." : stripped
    }

    /// Whether a failure means "unlock 1Password" rather than "something broke". "authorization"
    /// covers the family op actually emits: prompt dismissed, denied, and authorization timeout.
    static func indicatesLockedSession(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return ["not signed in", "authorization", "no account found",
                "no accounts configured", "connect to 1password", "connect to the 1password app",
                "connecting to desktop app", "session expired"]
            .contains { lowered.contains($0) }
    }

    /// Whether a failure is `op`'s desktop-app request timeout — worth one automatic retry, since a
    /// cold daemon can trip it once and then answer from its cache in seconds.
    static func indicatesTimeout(_ message: String) -> Bool {
        message.lowercased().contains("timed out")
    }

    /// Every whitespace-separated query token must match somewhere in the item's visible metadata.
    static func filtered(_ items: [OnePasswordItem], query: String) -> [OnePasswordItem] {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return items }
        return items.filter { item in
            let haystack = [
                item.title, item.username ?? "", item.vaultName,
                OnePasswordCategory.label(for: item.category), item.websiteURL ?? "",
            ].joined(separator: " ").lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}
