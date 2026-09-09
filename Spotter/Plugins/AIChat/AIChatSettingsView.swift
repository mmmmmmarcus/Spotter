import SwiftUI

struct AIChatSettingsView: View {
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @ObservedObject private var commands = AppCore.shared.aiCommands
    @State private var editor: AICommandEditorTarget?
    @State private var pendingDeletion: AICommand?

    var body: some View {
        SettingsPane(title: "AI Chat & Command") {
            OpenRouterSettingsCard()

            SettingsCard(header: "Chat") {
                SettingsRow(title: "Chat Model", subtitle: chatModelStatus) {
                    AIChatModelMenu(
                        brands: openRouter.catalog, selected: openRouter.chatModel,
                        chatModel: nil, set: { openRouter.setChatModel($0 ?? "") })
                }
                SettingsDivider()
                SettingsRow(title: "Model List", subtitle: catalogStatus) {
                    Button("Reload") { openRouter.refreshCatalog(force: true) }
                        .controlSize(.small)
                        .disabled(!openRouter.isReady || openRouter.catalogState == .loading)
                }
            }

            SettingsCard(header: "Commands") {
                ForEach(Array(commands.commands.enumerated()), id: \.element.id) { index, command in
                    if index > 0 { SettingsDivider() }
                    AICommandSettingsRow(
                        command: command,
                        brands: openRouter.catalog,
                        chatModel: openRouter.chatModel,
                        onEdit: { editor = AICommandEditorTarget(command: command) },
                        onDelete: { pendingDeletion = command })
                }
                SettingsDivider()
                SettingsRow(title: "Add AI Command") {
                    Button("Add…") { editor = AICommandEditorTarget(command: nil) }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Web Search") {
                SettingsRow(title: "Search the Web") {
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
        }
        // "Latest models" means what OpenRouter publishes when this pane is opened, not at launch.
        .onAppear { openRouter.refreshCatalog() }
        .sheet(item: $editor) { target in
            AICommandEditorSheet(command: target.command)
        }
        .alert(item: $pendingDeletion) { command in
            Alert(
                title: Text("Delete “\(command.name)”?"),
                message: Text("Its shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    AppCore.shared.deleteAICommand(id: command.id)
                },
                secondaryButton: .cancel())
        }
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

    private var chatModelStatus: String? {
        openRouter.isReady ? nil : "Inactive until an API key is added."
    }
}

private struct AICommandEditorTarget: Identifiable {
    let id = UUID()
    let command: AICommand?
}

private struct AICommandSettingsRow: View {
    let command: AICommand
    let brands: [OpenRouterModelBrand]
    let chatModel: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(command.name)
                    .font(.body)
                    .lineLimit(1)
                Text(command.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(command.prompt)
            }

            Spacer(minLength: Theme.Spacing.lg)
            AIChatModelMenu(
                brands: brands, selected: command.model, chatModel: chatModel,
                set: { AppCore.shared.aiCommands.setModel($0, for: command.id) })
            ShortcutRecorder(action: .aiCommand(id: command.id))

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Command")
            .accessibilityLabel("Edit \(command.name)")

            if let builtIn = command.builtIn {
                Button {
                    AppCore.shared.aiCommands.reset(builtIn)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .disabled(command.isDefault)
                .help("Reset to Spotter's prompt and model")
                .accessibilityLabel("Reset \(command.name)")
            } else {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete Command")
                .accessibilityLabel("Delete \(command.name)")
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

/// Brand → model, two levels deep: OpenRouter publishes hundreds of models, which is a menu rather
/// than a typed identifier. A stored model the live catalog doesn't carry stays selectable at the
/// top, so an older or withdrawn choice is never silently rewritten. Passing a `chatModel` adds the
/// Default row, which is what an AI command holds when it pins nothing.
private struct AIChatModelMenu: View {
    let brands: [OpenRouterModelBrand]
    let selected: String?
    /// The model a nil selection resolves to, or nil for the chat model's own row (which has no default).
    let chatModel: String?
    let set: (String?) -> Void

    var body: some View {
        Menu {
            if let chatModel {
                Section("Default") {
                    Toggle(
                        "Chat Model · \(OpenRouterModelCatalog.modelName(for: chatModel, in: brands) ?? chatModel)",
                        isOn: Binding(
                            get: { selected == nil }, set: { picked in if picked { set(nil) } }))
                }
            }
            if let selected, catalogLabel == nil {
                Section("Current") {
                    item(id: selected, name: selected)
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
            Text(label)
                .font(usesMonospacedLabel ? .body.monospaced() : .body)
        }
        .frame(width: 240)
    }

    private var catalogLabel: String? {
        selected.flatMap { OpenRouterModelCatalog.label(for: $0, in: brands) }
    }

    private var label: String {
        guard let selected else { return "Default" }
        return catalogLabel ?? selected
    }

    private var usesMonospacedLabel: Bool { selected != nil && catalogLabel == nil }

    private func item(id: String, name: String) -> some View {
        Toggle(
            name,
            isOn: Binding(
                get: { selected == id },
                set: { picked in if picked { set(id) } }))
    }
}

private struct AICommandEditorSheet: View {
    let command: AICommand?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    @State private var errorMessage: String?

    init(command: AICommand?) {
        self.command = command
        _name = State(initialValue: command?.name ?? "")
        _prompt = State(initialValue: command?.prompt ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(title)
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("Summarize Selected Text", text: $name)
                    .textFieldStyle(.roundedBorder)
                    // A built-in's name is Spotter's: the launcher, the docs and the shortcut list all promise it.
                    .disabled(command?.isBuiltIn == true)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Prompt")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Insert \(AICommand.placeholder)") { prompt += AICommand.placeholder }
                        .controlSize(.small)
                    if let builtIn = command?.builtIn {
                        Button("Reset to Default") {
                            prompt = AICommand.makeBuiltIn(builtIn).prompt
                        }
                        .controlSize(.small)
                    }
                }
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text(placeholderHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 520)
    }

    private var title: String {
        guard let command else { return "Add AI Command" }
        return "Edit \(command.name)"
    }

    private var placeholderHint: String {
        AICommandEngine.hasPlaceholder(prompt)
            ? "The selected text replaces every \(AICommand.placeholder)."
            : "No \(AICommand.placeholder) yet — the selected text will be appended after the prompt."
    }

    private func save() {
        // Editing keeps the UUID, and with it the command's shortcut, favorite and ranking references.
        let draft = AICommand(
            id: command?.id ?? UUID(), name: name, prompt: prompt,
            model: command?.model, builtIn: command?.builtIn)
        do {
            if command == nil {
                try AppCore.shared.addAICommand(draft)
            } else {
                try AppCore.shared.updateAICommand(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// OpenRouter credential card. The key is the gate: present means AI Chat and every AI command may
/// make requests; absent means fully on-device. Key and models sync through settings backups.
private struct OpenRouterSettingsCard: View {
    @ObservedObject private var store = AppCore.shared.openRouter
    @State private var keyDraft = AppCore.shared.openRouter.apiKey

    var body: some View {
        SettingsCard(header: "AI (OpenRouter)") {
            SettingsRow(
                title: "API Key", subtitle: keySubtitle,
                statusDot: store.isReady ? .green : nil
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    SecureField("sk-or-…", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { store.setAPIKey(keyDraft) }
                        .onChange(of: keyDraft) { store.setAPIKey(keyDraft) }
                    Button("Validate") {
                        Task { await store.validate() }
                    }
                    .controlSize(.small)
                    .disabled(keyDraft.isEmpty || store.validation == .checking)
                }
            }
        }
        // The key can change underneath this pane (settings sync applying a remote file).
        .onChange(of: store.apiKey) { if store.apiKey != keyDraft { keyDraft = store.apiKey } }
    }

    private var keySubtitle: String {
        switch store.validation {
        case .unknown:
            "Required for AI Chat, including selected-text definition and grammar. "
                + "Included in settings backups and sync."
        case .checking: "Checking key with \(OpenRouterStore.provider)…"
        case .valid(let detail): detail
        case .invalid(let message): message
        }
    }
}
