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
                SettingsDivider()
                SettingsRow(
                    title: "Resolution",
                    subtitle: "Retina captures at the display's native density; 1x captures one pixel per point.",
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    tint: .blue
                ) {
                    Picker("", selection: $screenshot.captureScale) {
                        ForEach(ScreenshotCaptureScale.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(
                    title: "Window Shadow",
                    subtitle: "Include the window's drop shadow when capturing a whole window.",
                    systemImage: "square.on.square.dashed",
                    tint: .blue
                ) {
                    Toggle("", isOn: $screenshot.includesWindowShadow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Saving") {
                SettingsRow(
                    title: "File Format",
                    subtitle: "Used by Save in the editor. JPG has no transparency, so it squares rounded corners; the clipboard copy stays lossless either way.",
                    systemImage: "doc",
                    tint: .blue
                ) {
                    Picker("", selection: $screenshot.fileFormat) {
                        ForEach(ScreenshotFileFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
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
