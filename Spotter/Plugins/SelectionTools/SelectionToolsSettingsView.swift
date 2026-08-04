import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @State private var translationModelDraft = AppCore.shared.openRouter.translationModel
    @State private var grammarModelDraft = AppCore.shared.openRouter.grammarModel

    var body: some View {
        SettingsPane(
            title: "Selection Tools",
            subtitle: "Use text selected in the frontmost app without touching the clipboard."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Selection Tools",
                    subtitle: "Search, translate, and check grammar from one native plugin.",
                    systemImage: "selection.pin.in.out", tint: .teal,
                    statusDot: plugins.isEnabled(.selectionTools) ? .green : nil
                ) {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "AI Models") {
                SettingsRow(
                    title: "Translation Model",
                    subtitle: aiSubtitle(
                        "Any OpenRouter model id; used by Translate Selected Text."),
                    systemImage: "translate", tint: .purple
                ) {
                    TextField(
                        OpenRouterStore.defaultTranslationModel, text: $translationModelDraft
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit { openRouter.setTranslationModel(translationModelDraft) }
                    .onChange(of: translationModelDraft) {
                        openRouter.setTranslationModel(translationModelDraft)
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Grammar Model",
                    subtitle: aiSubtitle(
                        "Any OpenRouter model id; used by Check Selected Text Grammar."),
                    systemImage: "text.badge.checkmark", tint: .purple
                ) {
                    TextField(OpenRouterStore.defaultGrammarModel, text: $grammarModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { openRouter.setGrammarModel(grammarModelDraft) }
                        .onChange(of: grammarModelDraft) {
                            openRouter.setGrammarModel(grammarModelDraft)
                        }
                }
            }
            // Models can change underneath this pane (settings sync applying a remote file).
            .onChange(of: openRouter.translationModel) {
                if openRouter.translationModel != translationModelDraft {
                    translationModelDraft = openRouter.translationModel
                }
            }
            .onChange(of: openRouter.grammarModel) {
                if openRouter.grammarModel != grammarModelDraft {
                    grammarModelDraft = openRouter.grammarModel
                }
            }

            SettingsCard(header: "Shortcuts") {
                shortcutRow(
                    title: "Search Selected Text",
                    subtitle: "Recommended: Hyper + S",
                    symbol: "magnifyingglass",
                    action: .searchSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Translate Selected Text",
                    subtitle: "Recommended: Hyper + T",
                    symbol: "translate",
                    action: .translateSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Check Selected Text Grammar",
                    subtitle: "Recommended: Hyper + G",
                    symbol: "text.badge.checkmark",
                    action: .checkSelectedTextGrammar)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(.selectionTools) },
            set: { plugins.setEnabled($0, for: .selectionTools) })
    }

    private func aiSubtitle(_ base: String) -> String {
        openRouter.isReady
            ? base
            : base + " Inactive — add an OpenRouter API key in Settings → General."
    }

    private func shortcutRow(
        title: String, subtitle: String, symbol: String, action: PluginActionKey
    ) -> some View {
        SettingsRow(
            title: title, subtitle: subtitle, systemImage: symbol, tint: .teal
        ) {
            ShortcutRecorder(action: .plugin(action))
        }
    }
}
