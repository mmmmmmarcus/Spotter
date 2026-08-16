import SwiftUI

struct AIChatSettingsView: View {
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @ObservedObject private var chat = AppCore.shared.aiChat

    var body: some View {
        SettingsPane(
            title: "AI Chat",
            subtitle: "Ask Spotter AI, send to ChatGPT on the web, or start from selected text."
        ) {
            if !openRouter.isReady {
                SettingsCallout(
                    title: "Spotter AI needs an OpenRouter API key.",
                    message:
                        "The key is entered once in General → AI. ChatGPT web remains available with Shift-Tab.",
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
                    selected: openRouter.chatModel,
                    fallback: OpenRouterStore.defaultChatModel,
                    set: openRouter.setChatModel)
                SettingsDivider()
                modelRow(
                    title: "Definition Model",
                    subtitle: "Used for the first Define Selected Text reply.",
                    symbol: "character.book.closed",
                    selected: openRouter.definitionModel,
                    fallback: OpenRouterStore.defaultDefinitionModel,
                    set: openRouter.setDefinitionModel)
                SettingsDivider()
                modelRow(
                    title: "Grammar Model",
                    subtitle: "Used for the first Check Selected Text Grammar reply.",
                    symbol: "text.badge.checkmark",
                    selected: openRouter.grammarModel,
                    fallback: OpenRouterStore.defaultGrammarModel,
                    set: openRouter.setGrammarModel)
                SettingsDivider()
                SettingsRow(
                    title: "Model List",
                    subtitle: catalogStatus,
                    systemImage: "arrow.clockwise", tint: .secondary
                ) {
                    Button("Reload") { openRouter.refreshCatalog(force: true) }
                        .controlSize(.small)
                        .disabled(!openRouter.isReady || openRouter.catalogState == .loading)
                }
            }

            SettingsCard(header: "Selected Text Prompts") {
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
                    title: "Define Selected Text", subtitle: "Recommended: Hyper + D",
                    symbol: "character.book.closed", action: .defineSelectedText)
                SettingsDivider()
                shortcutRow(
                    title: "Check Selected Text Grammar", subtitle: "Recommended: Hyper + G",
                    symbol: "text.badge.checkmark", action: .checkSelectedTextGrammar)
            }
        }
        // "Latest models" means what OpenRouter publishes when this pane is opened, not at launch.
        .onAppear { openRouter.refreshCatalog() }
    }

    private var catalogStatus: String {
        guard openRouter.isReady else {
            return "Loaded from \(OpenRouterStore.provider) once an API key is added."
        }
        switch openRouter.catalogState {
        case .idle: return "Not loaded yet."
        case .loading: return "Loading models from \(OpenRouterStore.provider)…"
        case .ready:
            let models = openRouter.catalog.reduce(0) { $0 + $1.models.count }
            return "\(models) models from \(openRouter.catalog.count) brands."
        case .failed(let reason): return reason
        }
    }

    private var definitionPromptBinding: Binding<String> {
        Binding(get: { chat.definitionPrompt }, set: { chat.setDefinitionPrompt($0) })
    }

    private var grammarPromptBinding: Binding<String> {
        Binding(get: { chat.grammarPrompt }, set: { chat.setGrammarPrompt($0) })
    }

    private func modelRow(
        title: String, subtitle: String, symbol: String, selected: String, fallback: String,
        set: @escaping (String) -> Void
    ) -> some View {
        SettingsRow(
            title: title,
            subtitle: openRouter.isReady
                ? subtitle : subtitle + " Inactive until an API key is added.",
            systemImage: symbol, tint: .purple
        ) {
            AIChatModelMenu(
                brands: openRouter.catalog, selected: selected, fallback: fallback, set: set)
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

/// Brand → model, two levels deep: OpenRouter publishes hundreds of models, which is a menu rather
/// than a typed identifier. A stored model the live catalog doesn't carry stays selectable at the
/// top, so an older or withdrawn choice is never silently rewritten.
private struct AIChatModelMenu: View {
    let brands: [OpenRouterModelBrand]
    let selected: String
    let fallback: String
    let set: (String) -> Void

    var body: some View {
        Menu {
            if catalogLabel == nil {
                Section("Current") {
                    item(id: selected, name: selected)
                    if selected != fallback {
                        item(id: fallback, name: "\(fallback) (default)")
                    }
                }
            }
            ForEach(brands) { brand in
                Menu(brand.title) {
                    ForEach(brand.models) { model in
                        item(id: model.id, name: model.name)
                    }
                }
            }
            if brands.isEmpty {
                Divider()
                Text("The model list hasn't loaded yet.")
            }
        } label: {
            Text(catalogLabel ?? selected)
                .font(catalogLabel == nil ? .body.monospaced() : .body)
        }
        .frame(width: 260)
    }

    private var catalogLabel: String? {
        OpenRouterModelCatalog.label(for: selected, in: brands)
    }

    private func item(id: String, name: String) -> some View {
        Toggle(
            name,
            isOn: Binding(
                get: { selected == id },
                set: { picked in if picked { set(id) } }))
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
