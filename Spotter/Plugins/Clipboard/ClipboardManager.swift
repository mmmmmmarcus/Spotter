import AppKit

@MainActor
final class ClipboardManager {
    static let internalType = ClipboardCapture.internalType

    private let store: ClipboardStore
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount = 0
    /// True while Selection Tools' ⌘C fallback transiently owns the pasteboard; polls in that window are marked seen without capturing.
    private var isSuppressed = false

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    // Isolated so teardown can touch the main-actor timer; AppCore only releases the manager on the main actor, so no hop. The poll block is `[weak self]`, so this isn't fixing a leak — it stops a stray timer firing if the manager is ever recreated.
    isolated deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func beginSuppressingCapture() {
        isSuppressed = true
    }

    func endSuppressingCapture() {
        // Sync to the current count so anything written during the window is treated as already seen.
        lastChangeCount = NSPasteboard.general.changeCount
        isSuppressed = false
    }

    private func poll() {
        let pb = NSPasteboard.general
        if isSuppressed {
            lastChangeCount = pb.changeCount
            return
        }
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.clipboardDisabledApps.contains(sourceBundleID) { return }
        guard let snapshot = ClipboardCapture.snapshot(pb) else { return }
        let store = store
        // Resolve pixels and file-backed copies off-main before falling back to their text representation.
        Task.detached(priority: .utility) {
            switch snapshot.resolve() {
            case .image(let png): await store.addImage(png, sourceBundleID: sourceBundleID)
            case .text(let text): await store.addText(text, sourceBundleID: sourceBundleID)
            case nil: break
            }
        }
    }
}
