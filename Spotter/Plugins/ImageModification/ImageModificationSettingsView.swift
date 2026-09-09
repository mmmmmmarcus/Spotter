import SwiftUI

struct ImageModificationSettingsView: View {
    @AppStorage("image-modification.output") private var output = ImageOutputLocation.alongside.rawValue
    @AppStorage("image-modification.format") private var format = ImageFormat.png.rawValue

    var body: some View {
        SettingsPane(title: "Image Modification") {
            Section("Defaults") {
                SettingsRow(title: "Output") {
                    Picker("", selection: $output) { ForEach(ImageOutputLocation.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
                SettingsRow(title: "Created Image Format") {
                    Picker("", selection: $format) { ForEach(ImageFormat.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
            }
        }
    }
}
