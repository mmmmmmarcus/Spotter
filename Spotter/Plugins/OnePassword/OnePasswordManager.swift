import AppKit
import Combine

/// Owns the 1Password plugin's live state: locating `op`, the in-memory item list, secret reveals
/// and the delayed clipboard clear. `AppCore` owns the single instance. Nothing 1Password returns
/// is ever written to disk — the item cache lives for the session and secrets only pass through.
@MainActor
final class OnePasswordManager: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case items([OnePasswordItem])
        case locked(String)
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isRefreshing = false
    /// Where `op` was found, or nil when it isn't installed — Settings and the palette both read this.
    @Published private(set) var binaryPath: String?
    /// The account uuid for `onepassword://` deep links; resolved lazily after the first item load.
    private(set) var accountID: String?

    /// Session-long metadata cache, shown instantly on reopen while a fresh list replaces it.
    private var itemsCache: [OnePasswordItem]?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var clipboardClearTask: Task<Void, Never>?

    private static let overrideKey = "one-password.cli-path"
    static let primaryActionKey = "one-password.primary-action"
    static let clearClipboardKey = "one-password.clear-clipboard"
    static let passwordLengthKey = "one-password.password-length"
    static let passwordDigitsKey = "one-password.password-digits"
    static let passwordSymbolsKey = "one-password.password-symbols"
    /// Matches 1Password's own default: a copied secret leaves the clipboard after 90 seconds.
    static let clipboardClearDelay: Double = 90

    init() {
        binaryPath = Self.locateBinary()
    }

    var isInstalled: Bool { binaryPath != nil }

    func setBinaryPathOverride(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.overrideKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.overrideKey)
        }
        binaryPath = Self.locateBinary()
    }

    var binaryPathOverride: String {
        UserDefaults.standard.string(forKey: Self.overrideKey) ?? ""
    }

    private static func locateBinary() -> String? {
        let fm = FileManager.default
        if let override = UserDefaults.standard.string(forKey: overrideKey),
            !override.isEmpty, fm.isExecutableFile(atPath: override)
        {
            return override
        }
        return OnePasswordCLI.searchPaths.first { fm.isExecutableFile(atPath: $0) }
    }

    // MARK: - Item list

    /// Screen open: the cached list shows instantly while a fresh one replaces it.
    func open() {
        binaryPath = Self.locateBinary()
        refresh()
    }

    /// Idempotent while a read is in flight: interrupting `op` would dismiss the 1Password
    /// authorization prompt it may be waiting on, so a reopen joins the running read instead.
    func refresh() {
        guard loadTask == nil else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        guard let path = binaryPath else {
            isRefreshing = false
            state = .idle
            return
        }
        state = itemsCache.map { .items($0) } ?? .loading
        isRefreshing = true
        startListLoad(path: path, generation: generation, attempt: 0)
    }

    private func startListLoad(path: String, generation: Int, attempt: Int) {
        loadTask = Task { [weak self] in
            let result = await OnePasswordProcessRunner.capture(
                path: path, arguments: OnePasswordCLI.listItemsArguments)
            guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
            self.loadTask = nil
            switch result {
            case .success(let data):
                self.isRefreshing = false
                guard let items = OnePasswordParser.parseItems(data) else {
                    self.state = .failed("1Password returned an unreadable item list.")
                    return
                }
                self.itemsCache = items
                self.state = .items(items)
                if self.accountID == nil { await self.fetchAccountID(path: path) }
            case .failure(let error):
                // One automatic retry on `op`'s desktop-app timeout: a cold daemon can trip it
                // once on a large vault and then answer from its cache in seconds.
                if attempt == 0, OnePasswordParser.indicatesTimeout(error.message) {
                    AppLog.info("1password", "Item list timed out; retrying once")
                    self.startListLoad(path: path, generation: generation, attempt: 1)
                    return
                }
                self.isRefreshing = false
                // A failed refresh keeps the stale list; an item action will surface the unlock prompt.
                if self.itemsCache != nil { return }
                if error.isLocked {
                    self.state = .locked(error.message)
                } else {
                    self.state = .failed(error.message)
                    AppLog.error("1password", "Listing items failed: \(error.message)")
                }
            }
        }
    }

    // Screen close deliberately leaves an in-flight read running: the palette hides the moment
    // 1Password's authorization window takes focus, and cancelling `op` then would kill the very
    // request being authorized. The finished read fills the session cache for the next open.

    /// Disable: drop everything held in memory. The pending clipboard clear stays armed on purpose.
    func reset() {
        loadTask?.cancel()
        loadTask = nil
        loadGeneration &+= 1
        isRefreshing = false
        itemsCache = nil
        accountID = nil
        state = .idle
    }

    private func fetchAccountID(path: String) async {
        // Best effort — a deep link without the account still resolves in a one-account setup.
        if case .success(let data) = await OnePasswordProcessRunner.capture(
            path: path, arguments: OnePasswordCLI.accountArguments)
        {
            accountID = OnePasswordParser.parseAccountID(data)
        }
    }

    // MARK: - Secrets

    /// Fetches one field at action time; the value exists only in the returned string.
    func revealSecret(
        item: OnePasswordItem, action: OnePasswordItemAction
    ) async -> Result<String, OnePasswordRunError> {
        guard let path = binaryPath else {
            return .failure(
                OnePasswordRunError(
                    message: "The 1Password CLI isn't installed.", isLocked: false))
        }
        let arguments: [String]
        if action.isOneTimePassword {
            arguments = OnePasswordCLI.oneTimePasswordArguments(
                itemID: item.id, vaultID: item.vaultID)
        } else if let field = action.field {
            arguments = OnePasswordCLI.readArguments(
                vaultID: item.vaultID, itemID: item.id, field: field)
        } else {
            return .failure(
                OnePasswordRunError(message: "This action reveals nothing.", isLocked: false))
        }
        return await OnePasswordProcessRunner.capture(path: path, arguments: arguments)
            .map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func generatePassword(
        length: Int, digits: Bool, symbols: Bool
    ) async -> Result<String, OnePasswordRunError> {
        guard let path = binaryPath else {
            return .failure(
                OnePasswordRunError(
                    message: "The 1Password CLI isn't installed.", isLocked: false))
        }
        let result = await OnePasswordProcessRunner.capture(
            path: path,
            arguments: OnePasswordCLI.generatePasswordArguments(
                length: length, digits: digits, symbols: symbols))
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let data):
            guard let password = OnePasswordParser.parseGeneratedPassword(data) else {
                return .failure(
                    OnePasswordRunError(
                        message: "1Password didn't return a password.", isLocked: false))
            }
            return .success(password)
        }
    }

    /// After a concealed copy: clear the pasteboard later unless something else owns it by then.
    func scheduleClipboardClear() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.clearClipboardKey) == nil
            || defaults.bool(forKey: Self.clearClipboardKey)
        else { return }
        let count = NSPasteboard.general.changeCount
        clipboardClearTask?.cancel()
        clipboardClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.clipboardClearDelay))
            guard !Task.isCancelled else { return }
            self?.clipboardClearTask = nil
            if NSPasteboard.general.changeCount == count {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
