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
            onDisable: { [weak core] in core?.screenshot.cancel() },
            settingsView: { AnyView(ScreenshotSettingsView()) })
    }
}

extension AppCore {
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
                hud.show(title: "Screenshot Copied", symbol: "checkmark.circle")
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
