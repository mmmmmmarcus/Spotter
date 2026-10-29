import AppKit
import SwiftUI

struct AIChatSettingsView: View {
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @ObservedObject private var localAI = AppCore.shared.localAI
    @ObservedObject private var commands = AppCore.shared.aiCommands
    @State private var editor: AICommandEditorTarget?
    @State private var pendingDeletion: AICommand?

    private func enterCLIPath(_ model: LocalAIModel) {
        let alert = NSAlert()
        alert.messageText = "\(model.title) Path"
        alert.informativeText = "Enter the absolute path to the executable. Leave empty to use automatic detection."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.stringValue = localAI.customPaths[model] ?? localAI.path(for: model) ?? ""
        field.placeholderString = "/path/to/\(model.executable)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        localAI.setCustomPath(field.stringValue, for: model)
    }

    var body: some View {
        SettingsPane(title: "AI Chat & Command") {
            Section("Multiple Providers") {
                OpenRouterSettingsSection()
                ForEach(LocalAIModel.allCases) { model in
                    SettingsRow(title: model.title,
                        subtitle: localAI.pathErrors[model] ?? localAI.path(for: model) ?? (localAI.isRefreshing ? "Checking…" : "Not found")) {
                        Button("Enter Path…") { enterCLIPath(model) }
                    }
                }
            }

            Section("Model Selection") {
                ForEach(AIRoutingCategory.allCases) { category in
                    VStack(spacing: Theme.Spacing.md) {
                        SettingsRow(title: category.title) {
                            AIChatModelMenu(brands: openRouter.catalog,
                                selected: openRouter.aiRouting.model(for: category),
                                chatModel: nil, set: { model in
                                    guard let model else { return }
                                    var preferences = openRouter.aiRouting
                                    preferences.setModel(model, for: category)
                                    openRouter.setAIRouting(preferences)
                                })
                        }
                        AIEffortSettingsRow(model: openRouter.aiRouting.model(for: category),
                            effort: Binding(get: { openRouter.aiRouting.effort(for: category) }, set: { effort in
                                var preferences = openRouter.aiRouting
                                preferences.setEffort(effort, for: category)
                                openRouter.setAIRouting(preferences)
                            }))
                    }
                }
            }

            Section {
                ForEach(commands.commands) { command in
                    AICommandSettingsRow(
                        command: command,
                        onEdit: { editor = AICommandEditorTarget(command: command) },
                        onDelete: { pendingDeletion = command })
                }
            } header: {
                Text("Commands")
            } footer: {
                SettingsListActions {
                    Button("Add…") { editor = AICommandEditorTarget(command: nil) }
                        .controlSize(.small)
                        .help("Add AI Command")
                        .accessibilityLabel("Add AI Command")
                }
            }

            AIToolSettingsSection()


        }
        // "Latest models" means what OpenRouter publishes when this pane is opened, not at launch.
        .onAppear { openRouter.refreshCatalog(force: true); localAI.refresh() }
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


}

private struct AICommandEditorTarget: Identifiable {
    let id = UUID()
    let command: AICommand?
}

/// The row names the command and offers its way in; the prompt, the model and the shortcut are that
/// command's own configuration and are set inside its editor rather than restated here.
private struct AICommandSettingsRow: View {
    let command: AICommand
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: command.name, systemImage: command.systemImage) {
            HStack(spacing: Theme.Spacing.md) {
                Button("Edit…", action: onEdit)
                    .controlSize(.small)
                    .accessibilityLabel("Edit \(command.name)")
                if let builtIn = command.builtIn {
                    Button("Reset") { AppCore.shared.aiCommands.reset(builtIn) }
                        .controlSize(.small)
                        .disabled(command.isDefault)
                        .help("Reset to Spotter's prompt and model")
                        .accessibilityLabel("Reset \(command.name)")
                } else {
                    Button("Delete", action: onDelete)
                        .controlSize(.small)
                        .accessibilityLabel("Delete \(command.name)")
                }
            }
        }
    }
}

/// Brand → model, two levels deep: OpenRouter publishes hundreds of models, which is a menu rather
/// than a typed identifier. A stored model the live catalog doesn't carry stays selectable at the
/// top, so an older or withdrawn choice is never silently rewritten. Passing a `chatModel` adds the
/// Default row, which is what an AI command holds when it pins nothing.
private struct AIChatModelMenu: View {
    @ObservedObject private var localAI = AppCore.shared.localAI
    let brands: [OpenRouterModelBrand]
    let selected: String?
    /// The model a nil selection resolves to, or nil for the chat model's own row (which has no default).
    let chatModel: String?
    var defaultLabel: String? = nil
    let set: (String?) -> Void

    var body: some View {
        Menu {
            Section("On This Mac") {
                Menu("Claude CLI") {
                    item(id: LocalAIModel.claude.id, name: "Use CLI Default")
                    ForEach(localAI.claudeModels.filter { $0.slug != "default" }) { model in item(id: model.id, name: model.title) }
                    if let selected, let model = LocalAIModel.claudeModelID(selected), !localAI.claudeModels.contains(where: { $0.id == selected }) {
                        item(id: selected, name: model)
                    }
                    if localAI.isRefreshing { Text("Loading models…") }
                }
                Menu("Codex CLI") {
                    item(id: LocalAIModel.codex.id, name: "Use CLI Default")
                    ForEach(localAI.codexModels) { model in item(id: model.id, name: model.title) }
                    if let selected, let model = LocalAIModel.codexModelID(selected), !localAI.codexModels.contains(where: { $0.id == selected }) {
                        item(id: selected, name: model)
                    }
                    if localAI.isRefreshing { Text("Loading models…") }
                    else if let error = localAI.codexCatalogError { Text(error) }
                }

            }
            if let chatModel {
                Section("Default") {
                    Toggle(
                        defaultLabel ?? "Chat Model · \(OpenRouterModelCatalog.modelName(for: chatModel, in: brands) ?? chatModel)",
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
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 240, alignment: .trailing)
    }

    private var catalogLabel: String? {
        guard let selected else { return nil }
        return LocalAIModel.label(selected) ?? OpenRouterModelCatalog.label(for: selected, in: brands)
    }

    private var label: String {
        guard let selected else { return defaultLabel ?? "Default" }
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
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @State private var name: String
    @State private var symbol: String
    @State private var prompt: String
    @State private var model: String?
    @State private var effort: String?
    @State private var errorMessage: String?

    init(command: AICommand?) {
        self.command = command
        _name = State(initialValue: command?.name ?? "")
        _symbol = State(initialValue: command?.systemImage ?? "sparkles")
        _prompt = State(initialValue: command?.prompt ?? "")
        _model = State(initialValue: command?.model)
        _effort = State(initialValue: command?.effort)
    }

    @State private var showsIconPicker = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, prompt }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            Text(command == nil ? "Add AI Command" : "Edit AI Command")
                .font(.title2.weight(.bold))

            identity
            promptEditor
            options

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Could not save: \(errorMessage)")
            }

            Divider()
            HStack(spacing: Theme.Spacing.md) {
                if let builtIn = command?.builtIn {
                    Button("Reset Prompt") { prompt = AICommand.makeBuiltIn(builtIn).prompt }
                        .disabled(prompt == AICommand.makeBuiltIn(builtIn).prompt)
                }
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
        .frame(width: Theme.AICommandEditor.width)
        .onAppear { focusedField = command == nil ? .name : .prompt }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            Button { showsIconPicker = true } label: {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: Theme.AICommandEditor.iconSize, height: Theme.AICommandEditor.iconSize)
                    .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(Theme.Spacing.xs)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
            .buttonStyle(.plain)
            .help("Choose Command Icon")
            .accessibilityLabel("Choose Command Icon")
            .accessibilityValue(symbol)
            .popover(isPresented: $showsIconPicker) {
                AICommandIconPicker(selected: symbol) {
                    symbol = $0
                    showsIconPicker = false
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name").font(.callout.weight(.medium))
                TextField("Command name", text: $name, prompt: Text("Summarize Selected Text"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focusedField, equals: .name)
                    .disabled(command?.isBuiltIn == true)
            }
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Prompt").font(.callout.weight(.medium))
            VStack(spacing: 0) {
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .prompt)
                    .accessibilityLabel("Prompt")
                    .padding(Theme.Spacing.md)
                    .frame(height: Theme.AICommandEditor.promptHeight)
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Describe what Spotter should do with the selected text…")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.md)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                Divider()
                HStack(spacing: Theme.Spacing.md) {
                    Text(placeholderHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.md)
                    Button("Insert Selection") {
                        prompt += AICommand.placeholder
                        focusedField = .prompt
                    }
                    .controlSize(.small)
                    .help("Insert \(AICommand.placeholder) into the prompt")
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            }
        }
    }

    private var options: some View {
        VStack(spacing: Theme.Spacing.xl) {
            SettingsRow(title: "Model") {
                AIChatModelMenu(
                    brands: openRouter.catalog, selected: model,
                    chatModel: openRouter.chatModel,
                    defaultLabel: "Automatic (Jev)", set: { if model != $0 { effort = nil }; model = $0 })
                    .accessibilityLabel("Command model")
            }
            AIEffortSettingsRow(model: model, effort: $effort)
            if let command {
                Divider()
                SettingsRow(title: "Shortcut") {
                    ShortcutRecorder(action: .aiCommand(id: command.id))
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var placeholderHint: String {
        AICommandEngine.hasPlaceholder(prompt)
            ? "Selected text replaces \(AICommand.placeholder)."
            : "Selected text is added automatically."
    }

    private func save() {
        guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
            errorMessage = "Enter a valid SF Symbol name."
            return
        }
        // Editing keeps the UUID, and with it the command's shortcut, favorite and ranking references.
        let draft = AICommand(
            id: command?.id ?? UUID(), name: name, prompt: prompt,
            model: model, builtIn: command?.builtIn, symbol: symbol, effort: effort)
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

private struct AICommandIconPicker: View {
    let selected: String
    let choose: (String) -> Void
    @State private var customSymbol: String

    private static let symbols = [
        "sparkles", "text.badge.checkmark", "textformat.abc", "text.bubble", "character.book.closed", "character.bubble",
        "doc.text", "list.bullet", "text.alignleft", "arrow.triangle.branch", "lightbulb", "brain.head.profile",
        "pencil", "pencil.line", "wand.and.stars", "globe", "curlybraces", "terminal",
        "envelope", "bubble.left.and.bubble.right", "megaphone", "graduationcap", "book", "checkmark.seal"
    ]

    init(selected: String, choose: @escaping (String) -> Void) {
        self.selected = selected
        self.choose = choose
        _customSymbol = State(initialValue: selected)
    }

    private var validCustomSymbol: String? {
        let value = customSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return NSImage(systemSymbolName: value, accessibilityDescription: nil) == nil ? nil : value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Command Icon").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Theme.AICommandEditor.symbolCellSize)), count: 6), spacing: Theme.Spacing.md) {
                ForEach(Self.symbols, id: \.self) { candidate in
                    Button { choose(candidate) } label: {
                        Image(systemName: candidate)
                            .font(.title3)
                            .frame(width: Theme.AICommandEditor.symbolCellSize, height: Theme.AICommandEditor.symbolCellSize)
                            .background(selected == candidate ? Theme.Colors.selection : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.menu))
                            .overlay {
                                if selected == candidate {
                                    RoundedRectangle(cornerRadius: Theme.Radius.menu)
                                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(candidate)
                    .accessibilityLabel(candidate)
                    .accessibilityAddTraits(selected == candidate ? .isSelected : [])
                }
            }
            Divider()
            Text("Custom SF Symbol").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.md) {
                TextField("SF Symbol name", text: $customSymbol)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if let value = validCustomSymbol { choose(value) } }
                Button("Use") { if let value = validCustomSymbol { choose(value) } }
                    .disabled(validCustomSymbol == nil)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.AICommandEditor.iconPickerWidth)
    }
}

/// OpenRouter credential card. The key is the gate: present means AI Chat and every AI command may
/// make requests; absent means fully on-device. Key and models sync through settings backups.
private struct OpenRouterSettingsSection: View {
    @ObservedObject private var store = AppCore.shared.openRouter
    @State private var keyDraft = AppCore.shared.openRouter.apiKey

    var body: some View {
        Group {
            SettingsRow(
                title: "OpenRouter API key", subtitle: keySubtitle,
                statusDot: store.isReady ? .green : nil
            ) {
                HStack(spacing: Theme.Spacing.md) {
                    SecureField("", text: $keyDraft)
                        .accessibilityLabel("OpenRouter API key")
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

    private var keySubtitle: String? {
        switch store.validation {
        case .unknown: nil
        case .checking: "Checking key with \(OpenRouterStore.provider)…"
        case .valid(let detail): detail
        case .invalid(let message): message
        }
    }
}

private struct AIEffortSettingsRow: View {
    @ObservedObject private var openRouter = AppCore.shared.openRouter
    @ObservedObject private var localAI = AppCore.shared.localAI
    let model: String?
    @Binding var effort: String?

    private var supported: [String] {
        guard let model else { return [] }
        return LocalAIModel.resolve(model) == nil ? openRouter.reasoningEfforts(for: model) : localAI.reasoningEfforts(for: model)
    }

    var body: some View {
        if !supported.isEmpty {
            SettingsRow(title: "Thinking effort") {
                Picker("Thinking effort", selection: Binding(
                    get: { AIReasoningEffort.resolve(effort, supported: supported) ?? "" },
                    set: { effort = $0.isEmpty ? nil : $0 })) {
                    Text("Model Default").tag("")
                    ForEach(supported, id: \.self) { Text(AIReasoningEffort.title($0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 240, alignment: .trailing)
            }
        }
    }
}
