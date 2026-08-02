import SwiftUI

struct TextReplacementSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: TextReplacementStore
    @ObservedObject var manager: TextReplacementManager
    @State private var prefixDraft: String
    @State private var editor: TextReplacementEditorTarget?
    @State private var pendingDeletion: TextReplacementRule?
    @State private var prefixError: String?

    init(store: TextReplacementStore, manager: TextReplacementManager) {
        self.store = store
        self.manager = manager
        _prefixDraft = State(initialValue: store.prefix)
    }

    var body: some View {
        SettingsPane(
            title: "Text Replacement",
            subtitle: "Expand memorable triggers into text wherever you type."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Text Replacement",
                    subtitle: "Watch for configured triggers and replace them in the active text field.",
                    systemImage: "text.badge.plus",
                    tint: .teal,
                    statusDot: statusDot
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.textReplacement) },
                            set: { plugins.setEnabled($0, for: .textReplacement) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if plugins.isEnabled(.textReplacement), manager.status == .needsAccessibility {
                SettingsCallout(
                    title: "Accessibility access is required.",
                    message: "Spotter needs permission to observe triggers and type their replacements.",
                    systemImage: "accessibility",
                    tint: .orange
                ) {
                    Button("Request Access…") { Permissions.ensureAccessibility() }
                }
            }

            SettingsCallout(
                title: "Your typing stays private.",
                message:
                    "Spotter keeps only a possible trigger suffix in memory, never stores or logs "
                    + "what you type, and inserts replacements without using the clipboard.",
                systemImage: "hand.raised.fill",
                tint: .teal)

            SettingsCard(header: "Trigger") {
                SettingsRow(
                    title: "Prefix",
                    subtitle: "Typed before every keyword. For example, @@ plus gmail becomes @@gmail.",
                    systemImage: "character.cursor.ibeam",
                    tint: .teal
                ) {
                    HStack(spacing: Theme.Spacing.md) {
                        TextField("@@", text: $prefixDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .frame(width: Theme.Size.textReplacementPrefixFieldWidth)
                            .onSubmit(savePrefix)
                        Button("Save", action: savePrefix)
                            .controlSize(.small)
                            .disabled(prefixDraft == store.prefix)
                    }
                }
                if let prefixError {
                    SettingsDivider()
                    SettingsRow(
                        title: "Invalid prefix",
                        subtitle: prefixError,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    ) { EmptyView() }
                }
            }

            SettingsCard(header: "Replacements") {
                if sortedRules.isEmpty {
                    SettingsRow(
                        title: "No replacements",
                        subtitle: "Add a keyword and the text it should expand into.",
                        systemImage: "text.badge.plus",
                        tint: .secondary
                    ) { EmptyView() }
                } else {
                    ForEach(Array(sortedRules.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { SettingsDivider() }
                        TextReplacementSettingsRow(
                            prefix: store.prefix, rule: rule,
                            onEdit: { editor = TextReplacementEditorTarget(rule: rule) },
                            onDelete: { pendingDeletion = rule })
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Add Replacement",
                    subtitle: "Create another keyword and replacement pair.",
                    systemImage: "plus.circle",
                    tint: .teal
                ) {
                    Button("Add…") { editor = TextReplacementEditorTarget(rule: nil) }
                        .controlSize(.small)
                }
            }
        }
        .sheet(item: $editor) { target in
            TextReplacementEditorSheet(store: store, rule: target.rule)
        }
        .alert(item: $pendingDeletion) { rule in
            Alert(
                title: Text("Delete “\(store.prefix)\(rule.keyword)”?"),
                message: Text("Typing this trigger will no longer expand its replacement."),
                primaryButton: .destructive(Text("Delete")) { store.delete(id: rule.id) },
                secondaryButton: .cancel())
        }
        .onChange(of: store.prefix) { prefixDraft = store.prefix }
    }

    private var sortedRules: [TextReplacementRule] {
        store.rules.sorted {
            $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
        }
    }

    private var statusDot: Color? {
        guard plugins.isEnabled(.textReplacement) else { return nil }
        switch manager.status {
        case .active: return .green
        case .needsAccessibility: return .orange
        case .off, .idle: return nil
        }
    }

    private func savePrefix() {
        do {
            try store.setPrefix(prefixDraft)
            prefixDraft = store.prefix
            prefixError = nil
        } catch {
            prefixError = error.localizedDescription
        }
    }
}

private struct TextReplacementSettingsRow: View {
    let prefix: String
    let rule: TextReplacementRule
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.teal)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(prefix + rule.keyword)
                    .font(.body.monospaced())
                    .lineLimit(1)
                Text(rule.replacement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(rule.replacement)
            }

            Spacer(minLength: Theme.Spacing.lg)
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help("Edit Replacement")
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Replacement")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

private struct TextReplacementEditorTarget: Identifiable {
    let id = UUID()
    let rule: TextReplacementRule?
}

private struct TextReplacementEditorSheet: View {
    @ObservedObject var store: TextReplacementStore
    let rule: TextReplacementRule?

    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String
    @State private var replacement: String
    @State private var errorMessage: String?

    init(store: TextReplacementStore, rule: TextReplacementRule?) {
        self.store = store
        self.rule = rule
        _keyword = State(initialValue: rule?.keyword ?? "")
        _replacement = State(initialValue: rule?.replacement ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(rule == nil ? "Add Replacement" : "Edit Replacement")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Trigger")
                    .font(.callout.weight(.medium))
                HStack(spacing: Theme.Spacing.md) {
                    Text(store.prefix)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    TextField("gmail", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Replacement")
                    .font(.callout.weight(.medium))
                TextEditor(text: $replacement)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.textReplacementEditorHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text("Example: \(store.prefix)gmail → abc@gmail.com")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

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
                        keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || replacement.isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.textReplacementEditorWidth)
    }

    private func save() {
        let draft = TextReplacementRule(
            id: rule?.id ?? UUID(), keyword: keyword, replacement: replacement)
        do {
            if rule == nil {
                try store.add(draft)
            } else {
                try store.update(draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
