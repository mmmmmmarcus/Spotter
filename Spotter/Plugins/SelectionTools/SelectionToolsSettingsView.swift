import SwiftUI

struct SelectionToolsSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @ObservedObject private var selectionTools = AppCore.shared.selectionTools
    @State private var translationModelDraft = AppCore.shared.openRouter.translationModel
    @State private var definitionModelDraft = AppCore.shared.openRouter.definitionModel
    @State private var grammarModelDraft = AppCore.shared.openRouter.grammarModel

    var body: some View {
        SettingsPane(
            title: "Selection Tools",
            subtitle: "Use text selected in the frontmost app without touching the clipboard."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Selection Tools",
                    subtitle: "Search, translate, define, and check grammar from one native plugin.",
                    systemImage: "selection.pin.in.out", tint: .teal
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
                    title: "Definition Model",
                    subtitle: aiSubtitle(
                        "Any OpenRouter model id; used by Define Selected Text."),
                    systemImage: "character.book.closed", tint: .purple
                ) {
                    TextField(OpenRouterStore.defaultDefinitionModel, text: $definitionModelDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { openRouter.setDefinitionModel(definitionModelDraft) }
                        .onChange(of: definitionModelDraft) {
                            openRouter.setDefinitionModel(definitionModelDraft)
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
            .onChange(of: openRouter.definitionModel) {
                if openRouter.definitionModel != definitionModelDraft {
                    definitionModelDraft = openRouter.definitionModel
                }
            }
            .onChange(of: openRouter.grammarModel) {
                if openRouter.grammarModel != grammarModelDraft {
                    grammarModelDraft = openRouter.grammarModel
                }
            }

            SettingsCard(header: "AI Prompts") {
                SelectionPromptEditor(
                    title: "Translation Prompt",
                    systemImage: "translate",
                    prompt: translationPromptBinding,
                    defaultPrompt: SelectionLLM.defaultTranslationSystemPrompt)
                SettingsDivider()
                SelectionPromptEditor(
                    title: "Definition Prompt",
                    systemImage: "character.book.closed",
                    prompt: definitionPromptBinding,
                    defaultPrompt: SelectionLLM.defaultDefinitionSystemPrompt)
                SettingsDivider()
                SelectionPromptEditor(
                    title: "Grammar Prompt",
                    systemImage: "text.badge.checkmark",
                    prompt: grammarPromptBinding,
                    defaultPrompt: SelectionLLM.defaultGrammarSystemPrompt)
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
                    title: "Define Selected Text",
                    subtitle: "Recommended: Hyper + D",
                    symbol: "character.book.closed",
                    action: .defineSelectedText)
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

    private var translationPromptBinding: Binding<String> {
        Binding(
            get: { selectionTools.translationPrompt },
            set: { selectionTools.setTranslationPrompt($0) })
    }

    private var definitionPromptBinding: Binding<String> {
        Binding(
            get: { selectionTools.definitionPrompt },
            set: { selectionTools.setDefinitionPrompt($0) })
    }

    private var grammarPromptBinding: Binding<String> {
        Binding(
            get: { selectionTools.grammarPrompt },
            set: { selectionTools.setGrammarPrompt($0) })
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

private struct SelectionPromptEditor: View {
    let title: String
    let systemImage: String
    @Binding var prompt: String
    let defaultPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.purple)
                    .frame(width: Theme.Size.settingsRowIcon)
                Text(title)
                    .font(.body)
                Spacer()
                Button("Reset to Default") { prompt = defaultPrompt }
                    .controlSize(.small)
            }
            TextEditor(text: $prompt)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: 112)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
