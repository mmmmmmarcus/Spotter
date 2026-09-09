import SwiftUI

struct WindowManagementSettingsView: View {
    @AppStorage(WindowManagementDefaults.gapKey) private var gap = 0
    @AppStorage(WindowManagementDefaults.cycleKey) private var cycleOnRepeat = false

    var body: some View {
        SettingsPane(title: "Window Management") {
            SettingsCard(header: "Layout") {
                SettingsRow(title: "Gap") {
                    Picker("", selection: $gap) {
                        Text("None").tag(0)
                        Text("4 pt").tag(4)
                        Text("8 pt").tag(8)
                        Text("12 pt").tag(12)
                        Text("16 pt").tag(16)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsDivider()
                SettingsRow(title: "Cycle on Repeat") {
                    Toggle("", isOn: $cycleOnRepeat)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }
}
