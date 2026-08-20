import AppKit
import SwiftUI

struct AboutView: View {
    // Loaded once and cached: reading the .icns is disk I/O, and body can re-run often. Read the
    // bundled file directly since NSApp.applicationIconImage returns the generic placeholder until
    // LaunchServices registers the app, which it hasn't when run from build/.
    @MainActor private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()

    private static let iconSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                // A tighter block rhythm than `SettingsPane`'s `xxl` so hero, links and support all land above the fold of the fixed-height Settings window.
                VStack(spacing: Theme.Spacing.xl) {
                    hero
                    links
                    support
                }
                // Ignore the transparent-titlebar safe area and use one fixed `xxl` inset every side, matching `SettingsPane`.
                .padding(Theme.Spacing.xxl)
                .frame(maxWidth: .infinity)
                .overlayScroller()
            }
            // Outside the scroll view so the copyright stays pinned to the pane's bottom edge, the way a real About window reads.
            footer
                .padding(.bottom, Theme.Spacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: Theme.Spacing.sm) {
                Text(Bundle.main.appDisplayName)
                    .font(.title.weight(.bold))
                Text(AppVersion.current.aboutLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .background(
                        Capsule().fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("A tiny, native macOS launcher.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var links: some View {
        SettingsCard(header: "Links") {
            // Rows paint a full-bleed hover fill, so the stack is clipped to the card's corner — otherwise the first/last row's highlight squares off the rounded ends.
            VStack(spacing: 0) {
                ForEach(AboutLink.all) { link in
                    if link.id != AboutLink.all.first?.id { SettingsDivider() }
                    AboutLinkRow(link: link)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    // No section header: the callout's own title is the header.
    private var support: some View {
        SettingsCallout(
            title: "Open Source",
            message:
                "Spotter is free and open source under AGPL-3.0. Issues, ideas and pull requests are welcome on GitHub.",
            systemImage: "bolt.fill",
            tint: Theme.Colors.brand
        )
    }

    // The upstream copyright stays alongside ours: much of the foundation is still Tinycast's code, and AGPL-3.0 requires preserving that notice.
    private var footer: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text("© 2026 Marcus Fei · Released under AGPL-3.0")
            Text("Based on Tinycast © 2026 Abue Ammar")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}

/// One external destination in the About "Links" card.
private struct AboutLink: Identifiable {
    enum Glyph {
        case symbol(String)
        /// A brand mark from `Assets.xcassets` (template SVG) — SF Symbols ships no GitHub logo.
        case brand(String)
    }

    let id: String
    let glyph: Glyph
    let title: String
    let detail: String
    let url: URL

    static let all: [AboutLink] = [
        AboutLink(
            id: "website", glyph: .symbol("globe"), title: "Website",
            detail: "mmmmmmarcus.github.io/Spotter",
            url: URL(string: "https://mmmmmmarcus.github.io/Spotter/")!),
        AboutLink(
            id: "github", glyph: .brand("BrandGitHub"), title: "GitHub",
            detail: "github.com/mmmmmmarcus/Spotter",
            url: URL(string: "https://github.com/mmmmmmarcus/Spotter")!),
        AboutLink(
            id: "upstream", glyph: .brand("BrandGitHub"), title: "Based on Tinycast",
            detail: "github.com/abue-ammar/tinycast",
            url: URL(string: "https://github.com/abue-ammar/tinycast")!),
    ]
}

/// A tappable row inside the About "Links" card: glyph, title, the destination in plain text, and the external-link arrow.
private struct AboutLinkRow: View {
    let link: AboutLink

    @State private var hovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            HStack(spacing: Theme.Spacing.lg) {
                glyph
                    .frame(width: Theme.Size.settingsRowIcon)
                    .foregroundStyle(.secondary)
                Text(link.title)
                    .font(.body)
                Spacer(minLength: Theme.Spacing.xl)
                Text(link.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hovered ? .secondary : .tertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .background(hovered ? Theme.Colors.rowHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var glyph: some View {
        switch link.glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
        case .brand(let name):
            // Brand marks paint edge to edge, so they sit a point under the SF Symbol box to read the same weight.
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
        }
    }
}

/// Hosts auxiliary SwiftUI windows (About, Settings), torn down on close so their SwiftUI trees deallocate instead of lingering, and rebuilt instantly on reopen from live state.
@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]
    private var resizeAnimations: [String: Task<Void, Never>] = [:]
    private var resizeAnimationTokens: [String: UUID] = [:]
    private let onWindowsChanged: () -> Void

    init(onWindowsChanged: @escaping () -> Void) {
        self.onWindowsChanged = onWindowsChanged
    }

    var hasOpenWindows: Bool { !windows.isEmpty }

    func isShowing(id: String) -> Bool { windows[id] != nil }

    /// Returns `true` when a new window was created, `false` when an existing one was re-raised.
    @discardableResult
    func show<Content: View>(
        id: String, title: String, size: CGSize, seamlessTitleBar: Bool = false,
        resizable: Bool = false, floating: Bool = false, transparent: Bool = false,
        minimumSize: CGSize? = nil, closeButtonOnly: Bool = false,
        contentExtendsIntoTitleBar: Bool = false, movableByBackground: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> Bool {
        let window: NSWindow
        let isNew: Bool
        if let existing = windows[id] {
            window = existing
            isNew = false
        } else {
            isNew = true
            var style: NSWindow.StyleMask = [.titled, .closable]
            if seamlessTitleBar { style.insert(.fullSizeContentView) }
            if resizable { style.insert(.resizable) }
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = title
            if let minimumSize { window.minSize = minimumSize }
            if transparent {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarSeparatorStyle = .none
            }
            if floating {
                window.level = .floating
                window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            }
            // Let the content run edge-to-edge under a transparent titlebar so the window reads as one continuous surface — the modern inspector look.
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                // Background dragging assumes every surface is chrome that controls opt out of. A window holding a drawing canvas opts out instead and supplies its own handle, since a bare gesture is not a control and would otherwise move the window mid-stroke.
                window.isMovableByWindowBackground = movableByBackground
            }
            if closeButtonOnly {
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
            }
            window.isReleasedWhenClosed = false
            let rootView = content()
            let hosting: NSHostingView<Content>
            if contentExtendsIntoTitleBar {
                hosting = FullWindowHostingView(rootView: rootView)
            } else {
                hosting = NSHostingView(rootView: rootView)
            }
            // Let the window keep its requested size instead of resizing to the SwiftUI fitting size (an unconstrained fill would otherwise blow the window up); the content fills the fixed frame.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.delegate = self
            window.center()
            windows[id] = window
        }
        // Auxiliary windows require regular-app activation for native layering; AppCore decides whether that policy remains after they close.
        onWindowsChanged()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // A plain `NSWindow` only becomes key while the app is active, but `NSApp.activate` from the menu bar is async, so the synchronous `makeKeyAndOrderFront` above can land first; re-asserting key on the next runloop makes the window truly key up front.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
        return isNew
    }

    func resizeHeight(id: String, to requestedHeight: CGFloat, animated: Bool = true) {
        guard let window = windows[id], requestedHeight.isFinite else { return }
        let screenLimit = window.screen?.visibleFrame.height ?? requestedHeight
        let height = min(max(requestedHeight, window.minSize.height), screenLimit)
        resizeAnimations[id]?.cancel()
        resizeAnimationTokens[id] = nil
        guard abs(window.frame.height - height) > 0.5 else { return }

        let startFrame = window.frame
        var targetFrame = startFrame
        targetFrame.size.height = height
        targetFrame.origin.y = startFrame.maxY - height
        guard animated, !window.inLiveResize else {
            window.setFrame(targetFrame, display: true)
            return
        }

        let token = UUID()
        resizeAnimationTokens[id] = token
        resizeAnimations[id] = Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            let startTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let progress = min(elapsed / Theme.Animation.quick, 1)
                let easedProgress = 1 - pow(1 - progress, 3)
                var frame = startFrame
                frame.size.height += (targetFrame.height - startFrame.height) * easedProgress
                frame.origin.y = startFrame.maxY - frame.height
                window.setFrame(frame, display: true)
                if progress >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            window.setFrame(targetFrame, display: true)
            if self.resizeAnimationTokens[id] == token {
                self.resizeAnimations[id] = nil
                self.resizeAnimationTokens[id] = nil
            }
        }
    }

    /// Close a window programmatically; `windowWillClose` handles the dict/teardown so the SwiftUI tree deallocates.
    func close(id: String) {
        windows[id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        resizeAnimations[id]?.cancel()
        resizeAnimations[id] = nil
        resizeAnimationTokens[id] = nil
        windows.removeValue(forKey: id)
        onWindowsChanged()
    }
}

private final class FullWindowHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    override var safeAreaRect: NSRect { bounds }
}
