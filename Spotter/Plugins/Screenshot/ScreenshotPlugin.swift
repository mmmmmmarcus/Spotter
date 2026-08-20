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
    private static let screenshotEditorWindowID = "screenshot-editor"

    /// The post-capture mark-up workspace; each capture opens fresh on the latest image.
    func showScreenshotEditor() {
        guard plugins.isEnabled(.screenshot), let capture = screenshot.lastCapture else { return }
        closePluginWindow(id: Self.screenshotEditorWindowID)
        showPluginWindow(
            id: Self.screenshotEditorWindowID,
            title: "Screenshot",
            size: Self.screenshotEditorWindowSize(for: capture.image),
            resizable: true,
            minimumSize: CGSize(width: 760, height: 420),
            contentExtendsIntoTitleBar: true,
            movableByBackground: false
        ) {
            ScreenshotEditorView(capture: capture)
        }
    }

    /// The capture's own thumbnail replaces a worded HUD: click it or press Return to edit.
    private func showScreenshotPreview() {
        guard let capture = screenshot.lastCapture else { return }
        screenshot.preview.onOpen = { [weak self] in self?.showScreenshotEditor() }
        screenshot.preview.show(capture.image)
    }

    func dismissScreenshotEditor() {
        closePluginWindow(id: Self.screenshotEditorWindowID)
        screenshot.clearLastCapture()
    }

    /// The capture at native points plus the toolbar, clamped into the visible frame.
    private static func screenshotEditorWindowSize(for image: CGImage) -> CGSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let toolbarHeight: CGFloat = 52
        let canvasPadding = Theme.Spacing.xl * 2
        let content = CGSize(
            width: CGFloat(image.width) / scale + canvasPadding,
            height: CGFloat(image.height) / scale + canvasPadding + toolbarHeight)
        let limit = (NSScreen.main?.visibleFrame.size).map {
            CGSize(width: $0.width * 0.85, height: $0.height * 0.85)
        } ?? CGSize(width: 1200, height: 800)
        return CGSize(
            width: min(max(content.width, 760), limit.width),
            height: min(max(content.height, 420), limit.height))
    }

    func captureScreenshot() {
        guard plugins.isEnabled(.screenshot) else {
            AppLog.info("screenshot", "Capture ignored because the plugin is disabled.")
            return
        }
        guard !screenshot.isCapturing else {
            AppLog.info("screenshot", "Capture ignored because a selection is already active.")
            return
        }
        AppLog.info("screenshot", "Capture request reached AppCore.")
        if isPaletteShowing { hidePalette() }
        screenshot.begin { [weak self] result in
            guard let self else { return }
            switch result {
            case .copied:
                showScreenshotPreview()
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
