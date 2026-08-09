import SwiftUI

struct AIChatSettingsView: View {
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @ObservedObject private var chat = AppCore.shared.aiChat
    @State private var chatModelDraft = AppCore.shared.openRouter.chatModel
    @State private var translationModelDraft = AppCore.shared.openRouter.translationModel
    @State private var definitionModelDraft = AppCore.shared.openRouter.definitionModel
    @State private var grammarModelDraft = AppCore.shared.openRouter.grammarModel

    var body: some View {
        SettingsPane(
            title: "AI Chat",
            subtitle: "Ask anything, or bring selected text into a conversation you can follow up."
        ) {
            if !openRouter.isReady {
                SettingsCallout(
                    title: "AI Chat needs an OpenRouter API key.",
                    message: "The key is entered once in General → AI and gates every AI request.",
                    systemImage: "key",
                    tint: .orange
                ) {
                    Button("Open General Settings…") { AppCore.shared.showSettings() }
                }
            }

            SettingsCard(header: "Models") {
                modelRow(
                    title: "Chat Model",
                    subtitle: "Used for regular messages and follow-ups.",
                    symbol: "bubble.left.and.bubble.right",
                    placeholder: OpenRouterStore.defaultChatModel,
                    text: $chatModelDraft,
                    set: openRouter.setChatModel)
                SettingsDivider()
                modelRow(
                    title: "Translation Model",
                    subtitle: "Used for the first Translate Selected Text reply.",
                    symbol: "translate",
                    placeholder: OpenRouterStore.defaultTranslationModel,
                    text: $translationModelDraft,
                    set: openRouter.setTranslationModel)
                SettingsDivider()
                modelRow(
                    title: "Definition Model",
                    subtitle: "Used for the first Define Selected Text reply.",
                    symbol: "character.book.closed",
                    placeholder: OpenRouterStore.defaultDefinitionModel,
                    text: $definitionModelDraft,
                    set: openRouter.setDefinitionModel)
                SettingsDivider()
                modelRow(
                    title: "Grammar Model",
                    subtitle: "Used for the first Check Selected Text Grammar reply.",
                    symbol: "text.badge.checkmark",
                    placeholder: OpenRouterStore.defaultGrammarModel,
                    text: $grammarModelDraft,
                    set: openRouter.setGrammarModel)
            }

            SettingsCard(header: "Selected Text Prompts") {
                AIChatPromptEditor(
                    title: "Translation Prompt", systemImage: "translate",
                    prompt: translationPromptBinding,
                    defaultPrompt: AIChatSelectionPrompts.defaultTranslation)
                SettingsDivider()
                AIChatPromptEditor(
                    title: "Definition Prompt", systemImage: "character.book.closed",
                    prompt: definitionPromptBinding,
                    defaultPrompt: AIChatSelectionPrompts.defaultDefinition)
                SettingsDivider()
                AIChatPromptEditor(
                    title: "Grammar Prompt", systemImage: "text.badge.checkmark",
                    prompt: grammarPromptBinding,
                    defaultPrompt: AIChatSelectionPrompts.defaultGrammar)
            }

            SettingsCard(header: "Web Search") {
                SettingsRow(
                    title: "Search the Web",
                    subtitle: "Lets regular replies and follow-ups cite current information. Selected-text first replies stay offline from web search.",
                    systemImage: "globe", tint: .purple
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { openRouter.chatWebSearch },
                            set: { openRouter.setChatWebSearch($0) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Shortcuts") {
                shortcutRow(
                    title: "Open AI Chat", subtitle: "Summon the conversation directly.",
                    symbol: "sparkles", action: .openAIChat)
                SettingsDivider()
                shortcutRow(
                    title: "Translate Selected Text", subtitle: "Recommended: Hyper + T",
                    symbol: "translate", action: .translateSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Define Selected Text", subtitle: "Recommended: Hyper + D",
                    symbol: "character.book.closed", action: .defineSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Check Selected Text Grammar", subtitle: "Recommended: Hyper + G",
                    symbol: "text.badge.checkmark", action: .checkSelectedTextGrammar)
            }
        }
        .onChange(of: openRouter.chatModel) { chatModelDraft = openRouter.chatModel }
        .onChange(of: openRouter.translationModel) {
            translationModelDraft = openRouter.translationModel
        }
        .onChange(of: openRouter.definitionModel) {
            definitionModelDraft = openRouter.definitionModel
        }
        .onChange(of: openRouter.grammarModel) { grammarModelDraft = openRouter.grammarModel }
    }

    private var translationPromptBinding: Binding<String> {
        Binding(get: { chat.translationPrompt }, set: { chat.setTranslationPrompt($0) })
    }

    private var definitionPromptBinding: Binding<String> {
        Binding(get: { chat.definitionPrompt }, set: { chat.setDefinitionPrompt($0) })
    }

    private var grammarPromptBinding: Binding<String> {
        Binding(get: { chat.grammarPrompt }, set: { chat.setGrammarPrompt($0) })
    }

    private func modelRow(
        title: String, subtitle: String, symbol: String, placeholder: String,
        text: Binding<String>, set: @escaping (String) -> Void
    ) -> some View {
        SettingsRow(
            title: title,
            subtitle: openRouter.isReady
                ? subtitle : subtitle + " Inactive until an API key is added.",
            systemImage: symbol, tint: .purple
        ) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(width: 260)
                .onSubmit { set(text.wrappedValue) }
                .onChange(of: text.wrappedValue) { set(text.wrappedValue) }
        }
    }

    private func shortcutRow(
        title: String, subtitle: String, symbol: String, action: PluginActionKey
    ) -> some View {
        SettingsRow(
            title: title, subtitle: subtitle, systemImage: symbol, tint: .purple
        ) {
            ShortcutRecorder(action: .plugin(action))
        }
    }
}

private struct AIChatPromptEditor: View {
    let title: String
    let systemImage: String
    @Binding var prompt: String
    let defaultPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.purple)
                    .frame(width: Theme.Size.settingsRowIcon)
                Text(title).font(.body)
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
