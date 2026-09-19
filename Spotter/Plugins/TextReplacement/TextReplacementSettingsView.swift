import SwiftUI

struct TextReplacementSettingsView: View {
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
        SettingsPane(title: "Snippets") {
            if manager.status == .needsAccessibility,
                store.snippets.contains(where: { $0.keyword != nil })
            {
                SettingsCallout(
                    title: "Accessibility access is required for expansion.",
                    message:
                        "Spotter needs permission to observe keyworded triggers and type their snippets. Palette search and paste work without it.",
                    tint: .orange
                ) {
                    Button("Request Access…") { Permissions.ensureAccessibility() }
                }
            }

            Section {
                if sortedSnippets.isEmpty {
                    SettingsRow(title: "No snippets") { EmptyView() }
                } else {
                    SnippetTableColumns {
                        Text("Trigger")
                    } content: {
                        Text("Original Text")
                    } actions: {
                        Text("Actions")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(sortedSnippets) { snippet in
                        SnippetSettingsRow(
                            prefix: store.prefix, snippet: snippet,
                            onEdit: { editor = SnippetEditorTarget(snippet: snippet) },
                            onDelete: { pendingDeletion = snippet })
                    }
                }
            } header: {
                Text("Snippets")
            } footer: {
                SettingsListActions {
                    Button("Add…") { editor = SnippetEditorTarget(snippet: nil) }
                        .controlSize(.small)
                        .accessibilityLabel("Add Snippet")
                }
            }

            Section("Expansion") {
                SettingsRow(title: "Prefix") {
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
                    SettingsRow(title: "Invalid prefix", subtitle: prefixError) { EmptyView() }
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

private struct SnippetTableColumns<Trigger: View, Content: View, Actions: View>: View {
    @ViewBuilder var trigger: Trigger
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            trigger.frame(width: 160, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
            actions.frame(width: 64, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SnippetSettingsRow: View {
    let prefix: String
    let snippet: Snippet
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SnippetTableColumns {
            if let keyword = snippet.keyword {
                Text(prefix + keyword)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(prefix + keyword)
                    .accessibilityLabel("Trigger: \(prefix + keyword)")
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .help("No typing trigger — available in the palette")
                    .accessibilityLabel("No typing trigger")
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(snippet.content)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(snippet.content)
                Text(snippet.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(snippet.name)
            }
        } actions: {
            HStack(spacing: Theme.Spacing.md) {
                Button(action: onEdit) { Image(systemName: "pencil").frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .help("Edit Snippet")
                    .accessibilityLabel("Edit \(snippet.name)")
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundStyle(.red).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Delete Snippet")
                .accessibilityLabel("Delete \(snippet.name)")
            }
        }
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
