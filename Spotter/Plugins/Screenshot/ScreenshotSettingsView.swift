import SwiftUI

struct ScreenshotSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var screenshot = AppCore.shared.screenshot

    var body: some View {
        SettingsPane(
            title: "Screenshot",
            subtitle: "Select any screen region and copy its pixels to the clipboard."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Screenshot",
                    subtitle: "Show a global crosshair for region capture.",
                    systemImage: "camera.viewfinder",
                    tint: .blue
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Capture") {
                SettingsRow(
                    title: "Rounded Corners",
                    subtitle: "Round the selection and copied image by 4 pixels.",
                    systemImage: "rectangle",
                    tint: .blue
                ) {
                    Toggle("", isOn: $screenshot.roundedCorners)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "Capture Screenshot",
                    subtitle: "Defaults to Option-Z and can be changed at any time.",
                    systemImage: "crop",
                    tint: .blue
                ) {
                    ShortcutRecorder(action: .plugin(.captureScreenshot))
                }
            }

            SettingsCallout(
                title: "Screen Recording permission required",
                message: "macOS protects screen pixels behind Screen Recording access. Spotter captures only after you invoke this action and stores the result only on the clipboard.",
                systemImage: "lock.shield")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.screenshot) },
            set: { plugins.setEnabled($0, for: .screenshot) })
    }
}
