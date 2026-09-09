import SwiftUI

struct ChangeCaseSettingsView: View {
    @ObservedObject var store: ChangeCaseStore
    @AppStorage("change-case.source") private var source = ChangeCaseInputSource.selectedText.rawValue
    @AppStorage("change-case.primary-action") private var primaryAction = ChangeCasePrimaryAction.paste.rawValue
    @AppStorage("change-case.preserve-case") private var preserveCase = true
    @AppStorage("change-case.preserve-punctuation") private var preservePunctuation = false
    @AppStorage("change-case.exceptions") private var exceptions = "iOS, iPadOS, iPhone, macOS, tvOS, watchOS"
    @AppStorage("change-case.prefix") private var prefix = ""
    @AppStorage("change-case.suffix") private var suffix = ""

    var body: some View {
        SettingsPane(title: "Change Case") {
            SettingsCard(header: "Input & Action") {
                SettingsRow(title: "Preferred Input") {
                    Picker("", selection: $source) { ForEach(ChangeCaseInputSource.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
                SettingsDivider()
                SettingsRow(title: "Primary Action") {
                    Picker("", selection: $primaryAction) { ForEach(ChangeCasePrimaryAction.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
                SettingsDivider()
                SettingsRow(title: "Preserve Casing") {
                    Toggle("", isOn: $preserveCase).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Preserve Punctuation") {
                    Toggle("", isOn: $preservePunctuation).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(header: "Casing Rules") {
                SettingsRow(title: "Exceptions") {
                    TextField("iOS, macOS", text: $exceptions).frame(width: 220)
                }
                SettingsDivider()
                SettingsRow(title: "Prefix Characters") {
                    TextField("Optional", text: $prefix).frame(width: 160)
                }
                SettingsDivider()
                SettingsRow(title: "Suffix Characters") {
                    TextField("Optional", text: $suffix).frame(width: 160)
                }
            }
            SettingsCard(header: "Cases") {
                ForEach(Array(ChangeCaseKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: kind.title) {
                        Toggle("", isOn: Binding(get: { store.isEnabled(kind) }, set: { store.setEnabled($0, kind: kind) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
        }
    }
}
