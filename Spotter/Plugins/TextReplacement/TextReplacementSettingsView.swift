import SwiftUI

struct TextReplacementSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: TextReplacementStore
    @ObservedObject var manager: TextReplacementManager
    @State private var prefixDraft: String
    @State private var editor: SnippetEditorTarget?
    @State private var pendingDeletion: Snippet?
    @State private var prefixError: String?

    init(store: TextReplacementStore, manager: TextReplacementManager) {
        self.store = store
        self.manager = manager
        _prefixDraft = State(initialValue: store.prefix)
    }

    var body: some View {
        SettingsPane(
            title: "Snippets",
            subtitle:
                "Reusable text to search and paste from the palette — give a snippet a keyword to expand it as you type."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "Snippets",
                    subtitle:
                        "Search snippets in the launcher, and expand the keyworded ones in any text field.",
                    systemImage: "text.badge.plus",
                    tint: .teal
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

            if plugins.isEnabled(.textReplacement), manager.status == .needsAccessibility,
                store.snippets.contains(where: { $0.keyword != nil })
            {
                SettingsCallout(
                    title: "Accessibility access is required for expansion.",
                    message:
                        "Spotter needs permission to observe keyworded triggers and type their snippets. Palette search and paste work without it.",
                    systemImage: "accessibility",
                    tint: .orange
                ) {
                    Button("Request Access…") { Permissions.ensureAccessibility() }
                }
            }

            SettingsCard(header: "Snippets") {
                if sortedSnippets.isEmpty {
                    SettingsRow(
                        title: "No snippets",
                        subtitle: "Add a named piece of text to paste from the palette.",
                        systemImage: "text.badge.plus",
                        tint: .secondary
                    ) { EmptyView() }
                } else {
                    ForEach(Array(sortedSnippets.enumerated()), id: \.element.id) { index, snippet in
                        if index > 0 { SettingsDivider() }
                        SnippetSettingsRow(
                            prefix: store.prefix, snippet: snippet,
                            onEdit: { editor = SnippetEditorTarget(snippet: snippet) },
                            onDelete: { pendingDeletion = snippet })
                    }
                }
                SettingsDivider()
                SettingsRow(
                    title: "Add Snippet",
                    subtitle: "Name it, write the text, and optionally give it an expansion keyword.",
                    systemImage: "plus.circle",
                    tint: .teal
                ) {
                    Button("Add…") { editor = SnippetEditorTarget(snippet: nil) }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Expansion") {
                SettingsRow(
                    title: "Prefix",
                    subtitle:
                        "Typed before every keyword. For example, @@ plus gmail becomes @@gmail.",
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
        }
        .sheet(item: $editor) { target in
            SnippetEditorSheet(store: store, snippet: target.snippet)
        }
        .alert(item: $pendingDeletion) { snippet in
            Alert(
                title: Text("Delete “\(snippet.name)”?"),
                message: Text(
                    snippet.keyword.map { "Typing \(store.prefix)\($0) will no longer expand." }
                        ?? "The snippet will leave the palette."),
                primaryButton: .destructive(Text("Delete")) { store.delete(id: snippet.id) },
                secondaryButton: .cancel())
        }
        .onChange(of: store.prefix) { prefixDraft = store.prefix }
    }

    private var sortedSnippets: [Snippet] {
        store.snippets.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
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

private struct SnippetSettingsRow: View {
    let prefix: String
    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: snippet.keyword == nil ? "text.quote" : "keyboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.teal)
                .frame(width: Theme.Size.settingsRowIcon)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(snippet.name)
                        .lineLimit(1)
                    if let keyword = snippet.keyword {
                        Text(prefix + keyword)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: Theme.Radius.keyCap, style: .continuous
                                )
                                .fill(Theme.Colors.controlSurface))
                    }
                }
                Text(snippet.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(snippet.content)
            }

            Spacer(minLength: Theme.Spacing.lg)
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help("Edit Snippet")
            Button(action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Snippet")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

private struct SnippetEditorTarget: Identifiable {
    let id = UUID()
    let snippet: Snippet?
}

private struct SnippetEditorSheet: View {
    @ObservedObject var store: TextReplacementStore
    let snippet: Snippet?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var content: String
    @State private var keyword: String
    @State private var errorMessage: String?

    init(store: TextReplacementStore, snippet: Snippet?) {
        self.store = store
        self.snippet = snippet
        _name = State(initialValue: snippet?.name ?? "")
        _content = State(initialValue: snippet?.content ?? "")
        _keyword = State(initialValue: snippet?.keyword ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(snippet == nil ? "Add Snippet" : "Edit Snippet")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("Work address", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Snippet")
                    .font(.callout.weight(.medium))
                TextEditor(text: $content)
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

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Expansion Keyword — optional")
                    .font(.callout.weight(.medium))
                HStack(spacing: Theme.Spacing.md) {
                    Text(store.prefix)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    TextField("gmail", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
                Text("Leave empty for a palette-only snippet. With a keyword, typing \(store.prefix)\(keyword.isEmpty ? "gmail" : keyword) anywhere expands into the snippet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                            || content.isEmpty)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.textReplacementEditorWidth)
    }

    private func save() {
        let draft = Snippet(
            id: snippet?.id ?? UUID(), name: name, content: content,
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : keyword)
        do {
            if snippet == nil {
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
