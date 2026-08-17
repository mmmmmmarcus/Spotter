import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var selectionTools = AppCore.shared.selectionTools
    @State private var apiKeyDraft = AppCore.shared.selectionTools.apiKey

    var body: some View {
        SettingsPane(
            title: "Selection Tools",
            subtitle: "Search selected text or translate it into the languages you choose."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Selection Tools",
                    subtitle: "Capture selected text without keeping a clipboard copy.",
                    systemImage: "selection.pin.in.out", tint: .teal
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.selectionTools) },
                            set: { plugins.setEnabled($0, for: .selectionTools) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if selectionTools.apiKey.isEmpty {
                SettingsCallout(
                    title: "Google Translate needs an API key.",
                    message:
                        "Create a Google Cloud project, enable Cloud Translation Basic, then paste its "
                        + "API key below. Without a key Spotter sends nothing to Google and Translate "
                        + "Selected Text stays unavailable.",
                    systemImage: "key", tint: .orange)
            }

            SettingsCard(header: "Google Translate") {
                SettingsRow(
                    title: "API Key",
                    subtitle:
                        "Each translation sends the selected text and this key to Google Cloud "
                        + "Translation Basic — one billable request per target language. Stored in "
                        + "bundle-scoped preferences and included in trusted sync or backup files.",
                    systemImage: "key", tint: .teal
                ) {
                    SecureField("Google Cloud API key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 260)
                        .onSubmit { selectionTools.setAPIKey(apiKeyDraft) }
                        .onChange(of: apiKeyDraft) { selectionTools.setAPIKey(apiKeyDraft) }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Connection",
                    subtitle: validationStatus,
                    systemImage: "network", tint: .secondary
                ) {
                    Button("Test API Key") {
                        Task { await selectionTools.validateAPIKey() }
                    }
                    .disabled(
                        selectionTools.apiKey.isEmpty || selectionTools.validation == .checking)
                }

                SettingsDivider()
                SettingsRow(
                    title: "Google Cloud setup",
                    subtitle: "Enable Cloud Translation and create a key for your project.",
                    systemImage: "arrow.up.right.square", tint: .secondary
                ) {
                    Link("Open Guide", destination: SelectionToolsManager.providerURL)
                }
            }

            SettingsCard(header: "Translate Into") {
                if selectionTools.targets.isEmpty {
                    SettingsRow(
                        title: "No target languages",
                        subtitle: "Add one below — without a target there is nothing to translate into.",
                        systemImage: "exclamationmark.triangle", tint: .orange
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(selectionTools.targets.enumerated()), id: \.element.id) {
                        index, language in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(
                            title: language.name,
                            subtitle:
                                "Skipped when the selection is already written in \(language.name).",
                            systemImage: "character.book.closed", tint: .teal
                        ) {
                            Button(role: .destructive) {
                                selectionTools.removeTarget(language.code)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(language.name)")
                        }
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Add a Language",
                    subtitle: "Every target gets its own row in the translation results.",
                    systemImage: "plus.circle", tint: .secondary
                ) {
                    Menu("Add") {
                        ForEach(selectionTools.availableTargets) { language in
                            Button(language.name) { selectionTools.addTarget(language.code) }
                        }
                    }
                    .frame(width: 120)
                    .disabled(selectionTools.availableTargets.isEmpty)
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "Search Selected Text",
                    subtitle: "Recommended: Hyper + S",
                    systemImage: "magnifyingglass", tint: .teal
                ) {
                    ShortcutRecorder(action: .plugin(.searchSelectedText))
                }
                SettingsDivider()
                SettingsRow(
                    title: "Translate Selected Text",
                    subtitle: "Recommended: Hyper + T",
                    systemImage: "translate", tint: .teal
                ) {
                    ShortcutRecorder(action: .plugin(.translateSelectedText))
                }
            }
        }
        .onChange(of: selectionTools.apiKey) {
            if selectionTools.apiKey != apiKeyDraft { apiKeyDraft = selectionTools.apiKey }
        }
    }

    private var validationStatus: String {
        switch selectionTools.validation {
        case .unknown: "Test the key with one short translation request."
        case .checking: "Testing Google Cloud Translation…"
        case .valid(let message), .invalid(let message): message
        }
    }
}
