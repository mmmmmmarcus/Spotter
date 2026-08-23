import Carbon.HIToolbox
import SwiftUI

extension PluginActionKey {
    static let captureScreenshot = standard(
        pluginID: .screenshot, actionID: "capture", title: "Capture Screenshot")
}

@MainActor
enum ScreenshotPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let capture: () -> Void = { [weak core] in
            core?.captureScreenshot()
        }
        let captureFromGlobalShortcut: () -> Void = { [weak core] in
            AppLog.info("screenshot", "Global shortcut dispatched; scheduling capture after the Carbon event.")
            DispatchQueue.main.async { [weak core] in
                core?.captureScreenshot()
            }
        }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .screenshot,
                name: "Screenshot",
                summary: "Select a region of any display and copy it to the clipboard.",
                systemImage: "camera.viewfinder",
                tint: .blue),
            defaultEnabled: true,
            permissions: [.screenRecording],
            shortcutActions: [
                PluginActionRegistration(
                    key: .captureScreenshot,
                    defaultShortcut: KeyShortcut(
                        carbonKeyCode: kVK_ANSI_Z, carbonModifiers: optionKey),
                    perform: captureFromGlobalShortcut)
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:screenshot:capture",
                    name: "Capture Screenshot",
                    systemImage: "camera.viewfinder",
                    actionKey: .captureScreenshot,
                    perform: capture)
            ],
            onDisable: { [weak core] in
                core?.screenshot.cancel()
                core?.dismissScreenshotEditor()
            },
            settingsView: { AnyView(ScreenshotSettingsView()) })
    }
}

extension AppCore {
    private static let screenshotEditorWindowID = ScreenshotEditorView.windowID

    /// The post-capture mark-up workspace; each capture opens fresh on the latest image.
    func showScreenshotEditor() {
        guard let capture = screenshot.lastCapture else { return }
        showScreenshotEditor(for: capture)
    }

    /// A pinned window edits the capture it holds, which is not necessarily the most recent one.
    func showScreenshotEditor(for capture: ScreenshotCapturePayload) {
        guard plugins.isEnabled(.screenshot) else { return }
        closePluginWindow(id: Self.screenshotEditorWindowID)
        showPluginWindow(
            id: Self.screenshotEditorWindowID,
            title: "Screenshot",
            size: Self.screenshotEditorWindowSize(for: capture.image),
            resizable: true,
            transparent: true,
            minimumSize: Self.screenshotEditorMinimumSize,
            hidesStandardButtons: true,
            clearsInitialFocus: true,
            contentExtendsIntoTitleBar: true,
            movableByBackground: false
        ) {
            ScreenshotEditorView(capture: capture)
        }
    }

    /// The capture's own thumbnail replaces a worded HUD: click it or press Return to edit, or drag
    /// it off to leave it pinned above every app. Each capture gets its own, so shots taken in
    /// quick succession queue up side by side.
    private func showScreenshotPreview(from sourceRect: CGRect?) {
        guard let capture = screenshot.lastCapture else { return }
        screenshot.showPreview(for: capture.image, from: sourceRect) { [weak self] in
            self?.showScreenshotEditor(for: capture)
        } onPin: { [weak self] thumbnail, point in
            guard let self else { return nil }
            return screenshot.pin(capture, thumbnail: thumbnail, at: point) { [weak self] pinned in
                self?.showScreenshotEditor(for: pinned)
            }
        }
    }

    func dismissScreenshotEditor() {
        closePluginWindow(id: Self.screenshotEditorWindowID)
        screenshot.clearLastCapture()
    }


    /// Wide enough for the action bar and no wider; a small capture now sits at 1:1 inside it
    /// rather than being stretched to fill.
    private static let screenshotEditorMinimumSize = CGSize(width: 620, height: 400)

    /// The capture at native points plus the toolbar, clamped into the visible frame.
    private static func screenshotEditorWindowSize(for image: CGImage) -> CGSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let toolbarHeight = ScreenshotEditorView.toolbarHeight
        let canvasPadding = Theme.Spacing.xl * 2
        let content = CGSize(
            width: CGFloat(image.width) / scale + canvasPadding,
            height: CGFloat(image.height) / scale + canvasPadding + toolbarHeight)
        let limit = (NSScreen.main?.visibleFrame.size).map {
            CGSize(width: $0.width * 0.85, height: $0.height * 0.85)
        } ?? CGSize(width: 1200, height: 800)
        return CGSize(
            width: min(max(content.width, screenshotEditorMinimumSize.width), limit.width),
            height: min(max(content.height, screenshotEditorMinimumSize.height), limit.height))
    }

    func captureScreenshot() {
        guard plugins.isEnabled(.screenshot) else {
            AppLog.info("screenshot", "Capture ignored because the plugin is disabled.")
            return
        }
        if screenshot.isCapturing {
            // The overlay is deliberately near-invisible, so the shortcut that opened it is the one
            // a stuck user reaches for. Make it the way out rather than a no-op.
            guard screenshot.acceptsShortcutCancel else {
                AppLog.info("screenshot", "Capture ignored; the selection only just opened.")
                return
            }
            AppLog.info("screenshot", "Shortcut pressed during a selection; cancelling it.")
            screenshot.cancel()
            return
        }
        AppLog.info("screenshot", "Capture request reached AppCore.")
        // Spotter's own windows only get out of the way when the user asks for it.
        if screenshot.hidesSpotterWindows {
            if isPaletteShowing { hidePalette() }
            closeAuxiliaryWindows()
        }
        screenshot.begin { [weak self] result in
            guard let self else { return }
            switch result {
            case .copied:
                showScreenshotPreview(from: screenshot.lastCaptureRect)
            case .textCopied:
                hud.show(title: "Text Copied", symbol: "text.viewfinder")
            case .noTextFound:
                hud.show(title: "No Text Found", symbol: "text.viewfinder", isNoOp: true)
            case .permissionRequired:
                hud.show(title: "Allow Screen Recording", symbol: "lock.shield", isNoOp: true)
            case .failed:
                hud.show(title: "Screenshot Failed", symbol: "exclamationmark.triangle", isNoOp: true)
            case .cancelled:
                break
            }
        }
    }
}
