import AppKit
import Combine
import Foundation

/// Drives the Quicklinks palette screen: which list is showing, and the step-by-step argument run.
/// Opening the resolved destination is the one side effect; everything else is state.
@MainActor
final class QuicklinkManager: ObservableObject {
    enum RunResult: Equatable {
        case opened
        case awaitingArguments
        case failed
    }

    enum Screen: Equatable {
        case list
        /// Collecting values for `pending`; one argument at a time.
        case arguments
    }

    /// One in-flight quicklink, filled left to right.
    struct PendingRun: Equatable {
        let quicklink: Quicklink
        let arguments: [QuicklinkArgument]
        var values: [String] = []

        var current: QuicklinkArgument? {
            values.count < arguments.count ? arguments[values.count] : nil
        }
        var isComplete: Bool { values.count >= arguments.count }
    }

    @Published private(set) var screen: Screen = .list
    @Published private(set) var pending: PendingRun?

    let store: QuicklinkStore
    /// Fired when a step completes, so `AppCore` can clear the palette query for the next prompt.
    var onStepAdvanced: (() -> Void)?

    init(store: QuicklinkStore) {
        self.store = store
    }

    func showList() {
        screen = .list
        pending = nil
    }

    /// Opens `quicklink` outright when it takes no arguments; otherwise starts the prompt run.
    /// Reports whether the destination opened, needs argument collection, or could not be resolved.
    @discardableResult
    func begin(_ quicklink: Quicklink) -> RunResult {
        let arguments = QuicklinkTemplate.arguments(in: quicklink.link)
        guard !arguments.isEmpty else {
            return open(quicklink, values: []) ? .opened : .failed
        }
        pending = PendingRun(quicklink: quicklink, arguments: arguments)
        screen = .arguments
        onStepAdvanced?()
        return .awaitingArguments
    }

    /// Accepts one argument value and reports whether another prompt remains.
    @discardableResult
    func submit(_ value: String) -> RunResult {
        guard var run = pending else { return .failed }
        run.values.append(value)
        pending = run
        guard run.isComplete else {
            onStepAdvanced?()
            return .awaitingArguments
        }
        let opened = open(run.quicklink, values: run.values)
        showList()
        return opened ? .opened : .failed
    }

    /// Steps back one argument, or leaves the run entirely when there is nothing to undo.
    func stepBack() {
        guard var run = pending else { return }
        guard !run.values.isEmpty else {
            showList()
            return
        }
        run.values.removeLast()
        pending = run
        onStepAdvanced?()
    }

    var placeholder: String? {
        guard screen == .arguments, let run = pending, let argument = run.current else { return nil }
        return "\(run.quicklink.name) — \(argument.name)…"
    }

    /// Resolves the template and hands the result to the chosen app, or the system default.
    func open(_ quicklink: Quicklink, values: [String]) -> Bool {
        let destination = QuicklinkDestination.detect(quicklink.link)
        let filled = QuicklinkTemplate.fill(
            quicklink.link, values: values, destination: destination)
        guard let url = Self.url(for: filled, destination: destination) else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        guard let bundleID = quicklink.openWithBundleID,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            return NSWorkspace.shared.open(url)
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        return true
    }

    /// Memoizes the Launch Services lookup below: the palette re-snapshots on every keystroke, and
    /// resolving a handler per row per keystroke is far more work than the icon is worth.
    private struct CachedOpener {
        let path: String?
    }

    private static var openerCache: [String: CachedOpener] = [:]

    /// Dropped when the list changes, so an edited destination re-resolves its icon.
    static func invalidateOpenerCache() {
        openerCache.removeAll()
    }

    /// The bundle whose icon represents this quicklink: the app it opens with, or whichever app
    /// macOS would hand the link to. Nil when nothing claims it, and the caller falls back to a symbol.
    static func openerBundlePath(for quicklink: Quicklink) -> String? {
        let key = (quicklink.openWithBundleID ?? "") + "\u{0}" + quicklink.link
        if let cached = openerCache[key] { return cached.path }
        let resolved = resolveOpenerBundlePath(for: quicklink)
        // A dictionary assignment of nil removes the key, so wrap it to memoize negative lookups.
        openerCache[key] = CachedOpener(path: resolved)
        return resolved
    }

    private static func resolveOpenerBundlePath(for quicklink: Quicklink) -> String? {
        if let bundleID = quicklink.openWithBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            return url.path
        }
        let destination = QuicklinkDestination.detect(quicklink.link)
        // Placeholders are filled with nothing: the handler follows from the scheme or extension,
        // and an unfilled template would not be a resolvable URL.
        let resolved = QuicklinkTemplate.fill(quicklink.link, values: [], destination: destination)
        guard let url = url(for: resolved, destination: destination) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)?.path
    }

    /// A bare `example.com` gets `https://`; a path becomes a file URL with `~` expanded.
    static func url(for link: String, destination: QuicklinkDestination) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch destination {
        case .file:
            if trimmed.hasPrefix("file:") { return URL(string: trimmed) }
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        case .web:
            if QuicklinkDestination.hasScheme(trimmed) { return URL(string: trimmed) }
            return URL(string: "https://" + trimmed)
        case .deeplink:
            return URL(string: trimmed)
        }
    }
}
