import SwiftUI

struct ImageModificationSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @AppStorage("image-modification.output") private var output = ImageOutputLocation.alongside.rawValue
    @AppStorage("image-modification.format") private var format = ImageFormat.png.rawValue

    var body: some View {
        SettingsPane(title: "Image Modification", subtitle: "A native toolbox powered by Core Image, Vision, and ImageIO.") {
            SettingsCard(header: "Plugin") {
                SettingsRow(title: "Image Modification", subtitle: "Runs locally and starts no background service.", systemImage: "photo.badge.arrow.down", tint: .teal) {
                    Toggle("", isOn: Binding(get: { plugins.isEnabled(.imageModification) }, set: { plugins.setEnabled($0, for: .imageModification) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(header: "Defaults") {
                SettingsRow(title: "Output", subtitle: "Convert Image asks for a format first; Replace Original always asks for confirmation.", systemImage: "folder", tint: .teal) {
                    Picker("", selection: $output) { ForEach(ImageOutputLocation.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
                SettingsDivider()
                SettingsRow(title: "Created Image Format", systemImage: "photo", tint: .teal) {
                    Picker("", selection: $format) { ForEach(ImageFormat.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
            }
            SettingsCard(header: "Command Shortcuts") {
                ForEach(Array(ImageOperation.allCases.enumerated()), id: \.element.id) { index, operation in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: operation.title, systemImage: operation.systemImage, tint: .teal) {
                        ShortcutRecorder(action: .plugin(.imageModification(operation)))
                    }
                }
            }
        }
    }
}
