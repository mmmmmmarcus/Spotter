import SwiftUI

struct ScreenshotSettingsView: View {
    @ObservedObject private var screenshot = AppCore.shared.screenshot

    var body: some View {
        SettingsPane(title: "Screenshot") {
            SettingsCard(header: "Capture") {
                SettingsRow(title: "Rounded Corners") {
                    Toggle("", isOn: $screenshot.roundedCorners)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Resolution") {
                    Picker("", selection: $screenshot.captureScale) {
                        ForEach(ScreenshotCaptureScale.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(title: "Hide Spotter While Capturing") {
                    Toggle("", isOn: $screenshot.hidesSpotterWindows)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Thumbnail Duration") {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField("", value: durationBinding, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        Text("sec")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Window Shadow") {
                    Toggle("", isOn: $screenshot.includesWindowShadow)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Saving") {
                SettingsRow(title: "File Format") {
                    Picker("", selection: $screenshot.fileFormat) {
                        ForEach(ScreenshotFileFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    /// Clamped on commit rather than rejected: a typed 0 or 900 becomes the nearest allowed value
    /// instead of leaving the field holding something the app will not honour.
    private var durationBinding: Binding<Double> {
        Binding(
            get: { screenshot.previewDuration },
            set: { screenshot.previewDuration = ScreenshotManager.clampPreviewDuration($0) })
    }
}
