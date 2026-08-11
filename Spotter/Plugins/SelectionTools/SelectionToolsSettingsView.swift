import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var selectionTools = AppCore.shared.selectionTools
    @State private var apiKeyDraft = AppCore.shared.selectionTools.apiKey
    @State private var askingConsent = false

    var body: some View {
        SettingsPane(
            title: "Selection Tools",
            subtitle: "Search selected text or translate it into Chinese and English."
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

            if selectionTools.isTranslationEnabled && selectionTools.apiKey.isEmpty {
                SettingsCallout(
                    title: "Google Translate needs an API key.",
                    message:
                        "Create a Google Cloud project, enable Cloud Translation Basic, then paste its API key below.",
                    systemImage: "key", tint: .orange)
            }

            SettingsCard(header: "Google Translate") {
                SettingsRow(
                    title: "Cloud Translation Basic",
                    subtitle: translationStatus,
                    systemImage: "translate", tint: .teal
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { selectionTools.isTranslationEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    selectionTools.setTranslationEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!plugins.isEnabled(.selectionTools))
                }

                SettingsDivider()
                SettingsRow(
                    title: "API Key",
                    subtitle: "Stored in bundle-scoped preferences and included in trusted sync or backup files.",
                    systemImage: "key", tint: .secondary
                ) {
                    SecureField("Google Cloud API key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 260)
                        .onSubmit { selectionTools.setAPIKey(apiKeyDraft) }
                        .onChange(of: apiKeyDraft) { selectionTools.setAPIKey(apiKeyDraft) }
                }

                if selectionTools.isTranslationEnabled {
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
                            selectionTools.apiKey.isEmpty
                                || selectionTools.validation == .checking)
                    }
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
        .sheet(isPresented: $askingConsent) {
            GoogleTranslationConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    selectionTools.setTranslationEnabled(true)
                })
        }
        .onChange(of: selectionTools.apiKey) {
            if selectionTools.apiKey != apiKeyDraft { apiKeyDraft = selectionTools.apiKey }
        }
    }

    private var translationStatus: String {
        if selectionTools.isTranslationEnabled {
            return "On · selected text is sent on demand for Chinese and English translation."
        }
        return "Off · no selected text is sent to Google."
    }

    private var validationStatus: String {
        switch selectionTools.validation {
        case .unknown: "Test the key with one short translation request."
        case .checking: "Testing Google Cloud Translation…"
        case .valid(let message), .invalid(let message): message
        }
    }
}

private struct GoogleTranslationConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "translate")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.teal)
                Text("Turn on Google Translate?")
                    .font(.headline)
            }

            Text(
                "Each time you run Translate Selected Text, Spotter sends the selected text and your "
                    + "API key to Google Cloud Translation Basic. It makes two requests—one for "
                    + "Simplified Chinese and one for English—using your project's billing and quota. "
                    + "Spotter does not cache the text or translations."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: SelectionToolsManager.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Google Cloud setup")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 440)
    }
}
