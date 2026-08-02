import AppKit
import SwiftUI

struct NoteView: View {
    @ObservedObject var store: NoteStore
    @State private var query = ""
    @State private var editRequest: NoteEditRequest?
    @State private var showsPreview = false

    private var visibleNotes: [SpotterNote] { store.filteredNotes(query: query) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.Colors.separator).frame(width: 1)
            editor
        }
        .background(VisualEffectView(material: .contentBackground, blending: .behindWindow))
        .ignoresSafeArea(edges: .top)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes").font(.title2.weight(.bold))
                Spacer()
                Button { createNote() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New Note")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xxl + Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)

            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Search Notes", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.md)

            if visibleNotes.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xs) {
                        ForEach(visibleNotes) { note in
                            NoteSidebarRow(
                                note: note, isSelected: store.selectedID == note.id,
                                select: { store.select(note) }, delete: { confirmDelete(note) })
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .overlayScroller()
            }

            Text("\(store.notes.count) \(store.notes.count == 1 ? "note" : "notes")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(Theme.Spacing.lg)
        }
        .frame(width: 230)
        .background(VisualEffectView(material: .sidebar, blending: .behindWindow))
    }

    @ViewBuilder
    private var editor: some View {
        if let note = store.selectedNote {
            VStack(spacing: 0) {
                editorToolbar(note)
                Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                if showsPreview {
                    NoteMarkdownPreview(markdown: note.content)
                } else {
                    ZStack(alignment: .topLeading) {
                        NoteMarkdownEditor(text: selectedContent, request: editRequest)
                        if note.content.isEmpty {
                            Text("Start writing…")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(Theme.Spacing.xxl)
                                .allowsHitTesting(false)
                        }
                    }
                }
                Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                editorFooter(note)
            }
        } else {
            ContentUnavailableView {
                Label("No Notes", systemImage: "note.text")
            } description: {
                Text("Create a note to start writing.")
            } actions: {
                Button("New Note") { createNote() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editorToolbar(_ note: SpotterNote) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(note.title).font(.headline).lineLimit(1)
            Spacer(minLength: Theme.Spacing.lg)
            if !showsPreview {
                formatButton("bold", help: "Bold", command: .bold, shortcut: "b")
                formatButton("italic", help: "Italic", command: .italic, shortcut: "i")
                formatButton("strikethrough", help: "Strikethrough", command: .strikethrough)
                formatButton("chevron.left.forwardslash.chevron.right", help: "Inline Code", command: .inlineCode)
                formatButton("link", help: "Link", command: .link)
                formatButton("textformat.size.larger", help: "Heading", command: .heading)
                formatButton("list.bullet", help: "Bulleted List", command: .bulletedList)
                formatButton("list.number", help: "Numbered List", command: .numberedList)
                formatButton("checklist", help: "Checklist", command: .checklist)
            }
            Button { showsPreview.toggle() } label: {
                Image(systemName: showsPreview ? "pencil" : "eye")
                    .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .help(showsPreview ? "Edit" : "Preview")
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.xxl + Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func editorFooter(_ note: SpotterNote) -> some View {
        let words = note.content.split(whereSeparator: { $0.isWhitespace }).count
        return HStack {
            Text("\(words) \(words == 1 ? "word" : "words") · \(note.content.count) characters")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            switch store.saveState {
            case .saved:
                Label("Saved", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .saving:
                ProgressView().controlSize(.mini)
                Text("Saving…").foregroundStyle(.secondary)
            case .failed:
                Label("Couldn’t Save", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.bottomBarHeight)
    }

    private func formatButton(
        _ image: String, help: String, command: NoteMarkdownCommand, shortcut: KeyEquivalent? = nil
    ) -> some View {
        let button = Button { editRequest = NoteEditRequest(command: command) } label: {
            Image(systemName: image)
                .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
        }
        .buttonStyle(.borderless)
        .help(help)
        if let shortcut {
            return AnyView(button.keyboardShortcut(shortcut, modifiers: .command))
        }
        return AnyView(button)
    }

    private var selectedContent: Binding<String> {
        Binding(
            get: { store.selectedNote?.content ?? "" },
            set: { store.updateSelectedContent($0) })
    }

    private func createNote() {
        query = ""
        showsPreview = false
        store.createNote()
    }

    private func confirmDelete(_ note: SpotterNote) {
        let alert = NSAlert()
        alert.messageText = "Delete “\(note.title)”?"
        alert.informativeText = "This note will be permanently deleted."
        alert.alertStyle = .warning
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        deleteButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn { store.delete(note) }
    }
}

private struct NoteSidebarRow: View {
    let note: SpotterNote
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(note.title).font(.headline).lineLimit(1)
                Text(note.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isSelected ? Theme.Colors.selection : hovering ? Theme.Colors.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Delete Note", role: .destructive, action: delete) }
        .onHover { hovering = $0 }
    }
}

private struct NoteMarkdownPreview: View {
    let markdown: String

    private var rendered: AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)))
            ?? AttributedString(markdown)
    }

    var body: some View {
        ScrollView {
            Text(rendered)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Theme.Spacing.xxl)
        }
        .overlayScroller()
    }
}
