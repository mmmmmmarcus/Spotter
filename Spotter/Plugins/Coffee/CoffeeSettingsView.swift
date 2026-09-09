import SwiftUI

struct CoffeeSettingsView: View {
    @ObservedObject private var coffee = AppCore.shared.coffee

    var body: some View {
        SettingsPane(title: "Caffeinate") {
            SettingsCard(header: "What Stays Awake") {
                SettingsRow(title: "Keep the Display On") {
                    Toggle("", isOn: $coffee.options.keepsDisplayAwake)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Keep Disks Spinning") {
                    Toggle("", isOn: $coffee.options.keepsDiskAwake)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }
}
