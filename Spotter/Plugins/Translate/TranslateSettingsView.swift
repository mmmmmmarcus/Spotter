import SwiftUI

struct TranslateSettingsView: View {
    @ObservedObject private var translate = AppCore.shared.translate
    @State private var apiKeyDraft = AppCore.shared.translate.apiKey

    var body: some View {
        SettingsPane(title: "Translate") {
            if translate.apiKey.isEmpty {
                SettingsCallout(
                    title: "Translate needs an API key.",
                    message:
                        "Create a Google Cloud project, enable Cloud Translation Basic, then paste its "
                        + "API key below. Without a key Spotter sends nothing to Google, and both "
                        + "Translate and Translate Selected Text stay unavailable.",
                    tint: .orange)
            }

            SettingsCard(header: "Google Cloud Translation") {
                SettingsRow(
                    title: "API Key",
                    subtitle:
                        "Each translation sends the text and this key to Google Cloud Translation "
                        + "Basic — one billable request per target language. The Translate page "
                        + "translates when you stop typing, never per keystroke, and never repeats "
                        + "text it has already translated into the same languages. Stored in "
                        + "bundle-scoped preferences and included in trusted sync or backup files."
                ) {
                    SecureField("Google Cloud API key", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 260)
                        .onSubmit { translate.setAPIKey(apiKeyDraft) }
                        .onChange(of: apiKeyDraft) { translate.setAPIKey(apiKeyDraft) }
                }

                SettingsDivider()
                SettingsRow(title: "Connection", subtitle: validationStatus) {
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
                    SettingsRow(title: "No target languages") {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(translate.targets.enumerated()), id: \.element.id) {
                        index, language in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(title: language.name) {
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
                SettingsRow(title: "Add a Language") {
                    Menu("Add") {
                        ForEach(translate.availableTargets) { language in
                            Button(language.name) { translate.addTarget(language.code) }
                        }
                    }
                    .frame(width: 120)
                    .disabled(translate.availableTargets.isEmpty)
                }
            }

        }
        .onChange(of: translate.apiKey) {
            if translate.apiKey != apiKeyDraft { apiKeyDraft = translate.apiKey }
        }
    }

    private var validationStatus: String? {
        switch translate.validation {
        case .unknown: nil
        case .checking: "Testing Google Cloud Translation…"
        case .valid(let message), .invalid(let message): message
        }
    }
}
