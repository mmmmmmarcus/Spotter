import SwiftUI

struct TranslateSettingsView: View {
    @ObservedObject private var translate = AppCore.shared.translate
    @State private var apiKeyDraft = AppCore.shared.translate.apiKey

    var body: some View {
        SettingsPane(
            title: "Translate",
            subtitle: "Translate typed or selected text into the languages you choose."
        ) {
            if translate.apiKey.isEmpty {
                SettingsCallout(
                    title: "Translate needs an API key.",
                    message:
                        "Create a Google Cloud project, enable Cloud Translation Basic, then paste its "
                        + "API key below. Without a key Spotter sends nothing to Google, and both "
                        + "Translate and Translate Selected Text stay unavailable.",
                    systemImage: "key", tint: .orange)
            }

            SettingsCard(header: "Google Cloud Translation") {
                SettingsRow(
                    title: "API Key",
                    subtitle:
                        "Each translation sends the text and this key to Google Cloud Translation "
                        + "Basic — one billable request per target language. The Translate page "
                        + "translates when you stop typing, never per keystroke, and never repeats "
                        + "text it has already translated into the same languages. Stored in "
                        + "bundle-scoped preferences and included in trusted sync or backup files.",
                    systemImage: "key", tint: .teal
                ) {
                    SecureField("Google Cloud API key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 260)
                        .onSubmit { translate.setAPIKey(apiKeyDraft) }
                        .onChange(of: apiKeyDraft) { translate.setAPIKey(apiKeyDraft) }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Connection",
                    subtitle: validationStatus,
                    systemImage: "network", tint: .secondary
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button("Test API Key") {
                            Task { await translate.validateAPIKey() }
                        }
                        .disabled(translate.apiKey.isEmpty || translate.validation == .checking)
                        Link("Open Guide", destination: TranslateManager.providerURL)
                    }
                }

                SettingsDivider()
                if translate.targets.isEmpty {
                    SettingsRow(
                        title: "No target languages",
                        subtitle: "Add one below — without a target there is nothing to translate into.",
                        systemImage: "exclamationmark.triangle", tint: .orange
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(translate.targets.enumerated()), id: \.element.id) {
                        index, language in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(
                            title: language.name,
                            subtitle:
                                "Skipped when the text is already written in \(language.name).",
                            systemImage: "character.book.closed", tint: .teal
                        ) {
                            Button(role: .destructive) {
                                translate.removeTarget(language.code)
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
                    subtitle: "Every target gets its own row — and its own billable request.",
                    systemImage: "plus.circle", tint: .secondary
                ) {
                    Menu("Add") {
                        ForEach(translate.availableTargets) { language in
                            Button(language.name) { translate.addTarget(language.code) }
                        }
                    }
                    .frame(width: 120)
                    .disabled(translate.availableTargets.isEmpty)
                }
            }

            SettingsCard(header: "Shortcuts") {
                SettingsRow(
                    title: "Translate",
                    subtitle: "Opens the Translate page, where the search field is the text.",
                    systemImage: "translate", tint: .teal
                ) {
                    ShortcutRecorder(action: .plugin(.translateText))
                }
                SettingsDivider()
                SettingsRow(
                    title: "Translate Selected Text",
                    subtitle: "Recommended: Hyper + T",
                    systemImage: "character.bubble", tint: .teal
                ) {
                    ShortcutRecorder(action: .plugin(.translateSelectedText))
                }
            }
        }
        .onChange(of: translate.apiKey) {
            if translate.apiKey != apiKeyDraft { apiKeyDraft = translate.apiKey }
        }
    }

    private var validationStatus: String {
        switch translate.validation {
        case .unknown: "Test the key with one short translation request."
        case .checking: "Testing Google Cloud Translation…"
        case .valid(let message), .invalid(let message): message
        }
    }
}
