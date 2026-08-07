import AppKit
import Combine

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    let symbolImage: String?
    /// A bundle to draw the icon from when the entry has no file of its own — a quicklink borrows the icon of the app that opens it. Overrides `symbolImage`.
    let iconFilePath: String?
    let pluginActionKey: PluginActionKey?
    /// Spotlight's `kMDItemAlternateNames`, ranked below the display name. Applications only.
    var alternateNames: [String] = []
    /// `CFBundleExecutable`, matched literally as a last resort. Applications only.
    var executableName: String?

    init(
        id: String, name: String, url: URL, bundleID: String?, kind: Kind,
        symbolImage: String? = nil, iconFilePath: String? = nil,
        pluginActionKey: PluginActionKey? = nil,
        alternateNames: [String] = [], executableName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.bundleID = bundleID
        self.kind = kind
        self.symbolImage = symbolImage
        self.iconFilePath = iconFilePath
        self.pluginActionKey = pluginActionKey
        self.alternateNames = alternateNames
        self.executableName = executableName
    }

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    var searchFields: SearchFields {
        SearchFields(
            names: [name], alternateNames: alternateNames,
            bundleID: bundleID, executableName: executableName)
    }

    var kindLabel: String {
        switch kind {
        case .application: return "Application"
        case .systemSettings: return "System Setting"
        case .command:
            return CustomCommand.id(fromEntryID: id) == nil ? "Command" : "Custom Command"
        }
    }

    /// The global-hotkey action for this entry, or `nil` for built-in commands and unaddressable bundles.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .command:
            if let pluginActionKey { return .plugin(pluginActionKey) }
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        }
    }

    /// Command entries are synthetic — no file behind them to reveal.
    var canRevealInFinder: Bool { kind != .command }

    /// Command entries draw an SF Symbol tile unless they borrowed a bundle; everything else uses its file icon.
    var isSymbolIcon: Bool { kind == .command && iconFilePath == nil }
    var symbolIconName: String {
        symbolImage ?? (CustomCommand.id(fromEntryID: id) == nil ? "questionmark" : "terminal")
    }

    /// The bundle whose icon this row draws, once it isn't a symbol tile.
    var iconPath: String { iconFilePath ?? url.path }

    var icon: NSImage {
        isSymbolIcon
            ? IconCache.symbolIcon(named: symbolIconName, dark: NSApp.effectiveAppearance.isDark)
            : IconCache.icon(forFile: iconPath)
    }
}

/// Caches app icons by file path, downsampled to a small fixed bitmap and byte-bounded, so list rows don't re-hit `NSWorkspace` or balloon memory.
enum IconCache {
    /// `NSCache` is thread-safe but not `Sendable`, so a detached decode populating what the main actor reads needs the guarantee asserted once here.
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    // 48pt (2× Retina) is plenty for the ≤24pt draw size, and keeping each icon small caps launcher memory since a scrolled `LazyVStack` pins every row's icon.
    private static let displayPixel: CGFloat = 48

    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// Cache-only lookups (never decode) so a row can paint an already-warm icon on the same frame.
    static func cached(forFile path: String) -> NSImage? { cache.object(forKey: path as NSString) }
    static func cachedSymbol(named name: String, dark: Bool) -> NSImage? {
        cache.object(forKey: symbolKey(name, dark: dark))
    }

    /// A symbol tile is rasterized, so its colors can't follow the appearance the way a live view's
    /// can — the appearance is part of the key instead, and a system flip simply draws a new one.
    /// Passed in rather than read from `NSApp`, since the decode runs off the main actor.
    private static func symbolKey(_ name: String, dark: Bool) -> NSString {
        (dark ? "symbol:dark:" : "symbol:light:") + name as NSString
    }

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable { let image: NSImage? }

    /// Return the decode directly (not a cache re-read) so an `NSCache` purge mid-decode can't strand a row on its placeholder. A missing path returns nil — not `NSWorkspace`'s broken-document icon — and never caches, so an uninstalled app can't leave a broken icon behind.
    static func loadAsync(forFile path: String) async -> NSImage? {
        if let cached = cached(forFile: path) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> Decoded in
            guard FileManager.default.fileExists(atPath: path) else { return Decoded(image: nil) }
            return Decoded(image: icon(forFile: path))
        }.value.image
    }
    static func loadSymbolAsync(named name: String, dark: Bool) async -> NSImage? {
        if let cached = cachedSymbol(named: name, dark: dark) { return cached }
        return await Task.detached(priority: .userInitiated) {
            Decoded(image: symbolIcon(named: name, dark: dark))
        }.value.image
    }

    static func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: path))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Command "icons": an SF Symbol on a rounded tile, in the same bitmap shape as app icons so rows treat every entry identically.
    static func symbolIcon(named name: String, dark: Bool) -> NSImage {
        let key = symbolKey(name, dark: dark)
        if let cached = cache.object(forKey: key) { return cached }
        let ink: NSColor = dark ? .white : .black

        let side = displayPixel
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Tile inset mirrors the margin macOS app icons carry inside their canvas.
            let tile = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 4, dy: 4)
            ink.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 9, yRadius: 9).fill()

            let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
                .applying(.init(paletteColors: [ink.withAlphaComponent(0.85)]))
            guard
                let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
            else { return true }
            let size = symbol.size
            symbol.draw(
                in: NSRect(
                    x: (side - size.width) / 2, y: (side - size.height) / 2,
                    width: size.width, height: size.height))
            return true
        }
        let (icon, cost) = downsampled(image)
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    /// Rasterize the multi-rep workspace icon into one `displayPixel`-square bitmap, returning it and its decoded byte cost.
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        // Fixed 2× (not `NSScreen.main`, which is main-thread-only) so this can rasterize on a detached decode; 96px covers the ≤24pt draw on any display.
        let pixels = Int(displayPixel * 2)
        let fallbackCost = Int(displayPixel * displayPixel * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPixel, height: displayPixel)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return (source, fallbackCost)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}

@MainActor
final class AppIndex: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    /// One-entry memo so repeated renders for the same query reuse the ranking instead of re-matching every frame.
    private var matchCache: (query: String, rankingRevision: Int, result: [AppEntry])?

    private var discoveredEntries: [AppEntry] = []
    private var spotlightCache = SpotlightNames.Cache()
    private var customCommandEntries: [AppEntry] = []
    private var pluginCommandEntries: [AppEntry] = []
    private var isRefreshing = false
    /// Set when a refresh is requested mid-scan, so a scope edit landing during an in-flight scan isn't silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private var settings: AppSettings?
    private var cancellables: Set<AnyCancellable> = []

    init(ranking: LauncherRankingStore) {
        self.ranking = ranking
    }

    /// Replaces the user-authored command slice without rescanning disk so Settings edits reach launcher search immediately.
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "spotter://custom-command/" + command.id.uuidString)!,
                bundleID: nil, kind: .command, symbolImage: "terminal")
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    /// Replaces the enabled plugin-command slice without rescanning disk.
    func setPluginCommands(_ commands: [AppEntry]) {
        let entries = commands.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard entries != pluginCommandEntries else { return }
        pluginCommandEntries = entries
        publishEntries()
    }

    /// Wires the search scopes, re-indexing when the user edits them so Settings changes land without waiting for the next launcher open.
    func start(settings: AppSettings) {
        self.settings = settings
        settings.$searchScopes
            .dropFirst()
            // @Published emits synchronously on the main actor (hence assumeIsolated), before the property is written, so the scan is deferred to a task that reads the settled value.
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)
    }

    /// Re-scan (called on every launcher open); overlapping reopens collapse into one trailing scan and `apps` is only re-published when the set changed, so an unchanged reopen does no UI work.
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            // The Spotlight cache rides across passes so a reopen re-reads only bundles whose modification date moved.
            let cache = spotlightCache
            let (found, updatedCache) = await Task.detached(priority: .utility) {
                AppIndex.scan(scopes: scopes, cache: SpotlightNames.Cache(reusing: cache))
            }.value
            spotlightCache = updatedCache
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
    }

    nonisolated private static func scan(
        scopes: [String], cache: SpotlightNames.Cache
    ) -> ([AppEntry], SpotlightNames.Cache) {
        var cache = cache
        var seenBundleIDs = Set<String>()
        var result: [AppEntry] = []
        for url in SearchScopes.appBundles(in: scopes) {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            // Dedup by bundle id; the earliest scope wins.
            if let bundleID, !seenBundleIDs.insert(bundleID).inserted { continue }

            let name =
                (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let executable = bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            result.append(
                AppEntry(
                    id: url.path, name: name, url: url, bundleID: bundleID,
                    kind: .application,
                    alternateNames: cache.alternateNames(for: url, displayName: name),
                    // A binary named after the app adds nothing the display name doesn't already cover.
                    executableName: executable.flatMap {
                        $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0
                    }))
        }
        // `publishEntries` appends commands after apps and Settings panes so the sectioned flat selection maps 1:1 onto rows.
        let apps = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
        return (apps + SettingsPaneScanner.scan(), cache)
    }

    private func publishEntries() {
        // The System Commands plugin republishes the legacy quit-all id; the plugin's entry wins so
        // the row follows its enable state, and the registry fallback only shows when it's off.
        let pluginIDs = Set(pluginCommandEntries.map(\.id))
        let builtIns = CommandRegistry.all.filter { !pluginIDs.contains($0.id) }
        let commands = (builtIns + pluginCommandEntries + customCommandEntries).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let updated = discoveredEntries + commands
        guard updated != apps else { return }
        apps = updated
        matchCache = nil
    }

    /// Ranked matches. Empty query returns the full alphabetical list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        if let matchCache, matchCache.query == q,
            matchCache.rankingRevision == ranking.revision
        {
            return matchCache.result
        }
        let result = rank(q, limit: limit)
        matchCache = (q, ranking.revision, result)
        return result
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        let learned = ranking.boosts(query: q)
        let scored = apps.compactMap { app -> (AppEntry, Int)? in
            guard let score = SearchRelevance.score(query: q, fields: app.searchFields) else {
                return nil
            }
            return (app, score + (learned[app.preferenceKey] ?? 0))
        }
        return
            scored
            .sorted {
                $0.1 != $1.1
                    ? $0.1 > $1.1
                    : $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }
}
