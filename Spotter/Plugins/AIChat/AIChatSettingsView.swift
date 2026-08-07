import SwiftUI

struct AIChatSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @State private var modelDraft = AppCore.shared.openRouter.chatModel

    var body: some View {
        SettingsPane(
            title: "AI Chat",
            subtitle: "A conversation in the palette — Tab from the launcher, or run the AI Chat command."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "AI Chat",
                    subtitle: "Ask follow-ups in one running conversation, at launcher size.",
                    systemImage: "sparkles", tint: .purple,
                    statusDot: openRouter.isReady ? .green : .orange
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.aiChat) },
                            set: { plugins.setEnabled($0, for: .aiChat) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if !openRouter.isReady {
                SettingsCallout(
                    title: "AI Chat needs an OpenRouter API key.",
                    message: "The key is shared with Selection Tools and entered there once.",
                    systemImage: "key",
                    tint: .orange
                ) {
                    Button("Open Selection Tools…") {
                        AppCore.shared.showSettings(plugin: .selectionTools)
                    }
                }
            }

            SettingsCard(header: "Model") {
                SettingsRow(
                    title: "Chat Model",
                    subtitle: "Any OpenRouter model id. Chat defaults a class up from the quick selection actions.",
                    systemImage: "cpu", tint: .purple
                ) {
                    TextField(OpenRouterStore.defaultChatModel, text: $modelDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(width: 260)
                        .onSubmit { openRouter.setChatModel(modelDraft) }
                        .onChange(of: modelDraft) { openRouter.setChatModel(modelDraft) }
                }
            }

            SettingsCard(header: "Web Search") {
                SettingsRow(
                    title: "Search the Web",
                    subtitle: "Lets replies cite current information through OpenRouter's web plugin. Adds a small per-message cost on your key.",
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

            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "Open AI Chat",
                    subtitle: "Summon the palette straight into the conversation.",
                    systemImage: "sparkles", tint: .purple
                ) {
                    ShortcutRecorder(action: .plugin(.openAIChat))
                }
            }

            SettingsCallout(
                title: "Conversations stay in this session.",
                message:
                    "Nothing is saved to disk: quitting Spotter, or New Conversation in the ⌘K menu, "
                    + "clears the transcript. Messages go only to OpenRouter, using your own key.",
                systemImage: "hand.raised")
        }
        .onChange(of: openRouter.chatModel) { modelDraft = openRouter.chatModel }
    }
}
