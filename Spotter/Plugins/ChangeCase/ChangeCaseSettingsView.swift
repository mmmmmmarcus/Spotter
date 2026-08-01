import SwiftUI

struct ChangeCaseSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: ChangeCaseStore
    @AppStorage("change-case.source") private var source = ChangeCaseInputSource.selectedText.rawValue
    @AppStorage("change-case.primary-action") private var primaryAction = ChangeCasePrimaryAction.paste.rawValue
    @AppStorage("change-case.preserve-case") private var preserveCase = true
    @AppStorage("change-case.preserve-punctuation") private var preservePunctuation = false
    @AppStorage("change-case.exceptions") private var exceptions = "iOS, iPadOS, iPhone, macOS, tvOS, watchOS"
    @AppStorage("change-case.prefix") private var prefix = ""
    @AppStorage("change-case.suffix") private var suffix = ""

    var body: some View {
        SettingsPane(title: "Change Case", subtitle: "Transform selected or copied text with native, offline commands.") {
            SettingsCard(header: "Plugin") {
                SettingsRow(title: "Change Case", subtitle: "Includes the browser and 21 direct commands.", systemImage: "textformat", tint: .purple, statusDot: plugins.isEnabled(.changeCase) ? .green : nil) {
                    Toggle("", isOn: Binding(get: { plugins.isEnabled(.changeCase) }, set: { plugins.setEnabled($0, for: .changeCase) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(header: "Input & Action") {
                SettingsRow(title: "Preferred Input", subtitle: "Falls back to the other source when unavailable.", systemImage: "selection.pin.in.out", tint: .purple) {
                    Picker("", selection: $source) { ForEach(ChangeCaseInputSource.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
                SettingsDivider()
                SettingsRow(title: "Primary Action", subtitle: "Used by direct launcher commands and global shortcuts.", systemImage: "return", tint: .purple) {
                    Picker("", selection: $primaryAction) { ForEach(ChangeCasePrimaryAction.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden()
                }
                SettingsDivider()
                SettingsRow(title: "Preserve Casing", subtitle: "Keep existing word boundaries before applying the transformation.", systemImage: "textformat.abc", tint: .purple) {
                    Toggle("", isOn: $preserveCase).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(title: "Preserve Punctuation", subtitle: "Keep punctuation for lower- and uppercase transforms.", systemImage: "character.cursor.ibeam", tint: .purple) {
                    Toggle("", isOn: $preservePunctuation).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            SettingsCard(header: "Casing Rules") {
                SettingsRow(title: "Exceptions", subtitle: "Comma-separated words whose exact spelling is preserved in Sentence and Title Case.", systemImage: "text.badge.checkmark", tint: .purple) {
                    TextField("iOS, macOS", text: $exceptions).frame(width: 220)
                }
                SettingsDivider()
                SettingsRow(title: "Prefix Characters", subtitle: "Characters retained at the beginning of a value.", systemImage: "arrow.left.to.line", tint: .purple) {
                    TextField("Optional", text: $prefix).frame(width: 160)
                }
                SettingsDivider()
                SettingsRow(title: "Suffix Characters", subtitle: "Characters retained at the end of a value.", systemImage: "arrow.right.to.line", tint: .purple) {
                    TextField("Optional", text: $suffix).frame(width: 160)
                }
            }
            SettingsCard(header: "Cases") {
                ForEach(Array(ChangeCaseKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: kind.title, systemImage: kind.systemImage, tint: .purple) {
                        Toggle("", isOn: Binding(get: { store.isEnabled(kind) }, set: { store.setEnabled($0, kind: kind) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
            }
            SettingsCard(header: "Shortcut") {
                SettingsRow(title: "Change Case", subtitle: "Open the transformation browser.", systemImage: "keyboard", tint: .purple) {
                    ShortcutRecorder(action: .plugin(.openChangeCase))
                }
            }
        }
    }
}
