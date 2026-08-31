import AppKit
import SwiftUI

struct NoteView: View {
    @ObservedObject var store: NoteStore
    let resizeHeight: (CGFloat, Bool) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var showsNoteList = false
    @State private var editorHeight: CGFloat
    @State private var placeholderStamp = Date()
    @FocusState private var searchIsFocused: Bool

    init(
        store: NoteStore, resizeHeight: @escaping (CGFloat, Bool) -> Void,
        close: @escaping () -> Void
    ) {
        self.store = store
        self.resizeHeight = resizeHeight
        self.close = close
        _editorHeight = State(
            initialValue: NoteEditorMetrics.estimatedEditorHeight(
                for: store.selectedNote?.content ?? ""))
    }

    private var visibleNotes: [SpotterNote] { store.filteredNotes(query: query) }

    var body: some View {
        VStack(spacing: 0) {
            // Deliberately outside the animated container below: inside it, every list toggle put the
            // title and its trailing buttons through the same animated relayout as the list, so the
            // toolbar drifted on a change that has nothing to do with it.
            editorToolbar

            ZStack(alignment: .top) {
                editorContent

                if showsNoteList {
                    noteList
                        .padding(.horizontal, Theme.Spacing.xxl)
                        // The token measures from the window's top edge; the toolbar is now a sibling
                        // above this container, so its height comes out of the inset.
                        .padding(.top, Theme.Size.noteListTopInset - Theme.Size.noteToolbarHeight)
                        .padding(.bottom, Theme.Spacing.xxl)
                        .transition(
                            .scale(scale: 0.98, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeOut(duration: Theme.Animation.quick), value: showsNoteList)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { placeholderStamp = Date() }
        .onDisappear { store.deleteEmptyNotes() }
        .onChange(of: store.selectedID) { placeholderStamp = Date() }
        .ignoresSafeArea(edges: .top)
        .background(tintWash)
        .background(Theme.Colors.panelScrim.opacity(1 - store.windowTransparency))
        .background(VisualEffectView(material: .hudWindow, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
    }

    @ViewBuilder private var tintWash: some View {
        if let tint = store.selectedNote?.tint {
            Theme.Colors.noteTintWash(tint)
        }
    }

    private var noteList: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search for notes…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(height: Theme.Size.headerHeight)

            Rectangle().fill(Theme.Colors.separator).frame(height: 1)

            if visibleNotes.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xs) {
                        ForEach(visibleNotes) { note in
                            NoteListRow(
                                note: note, isSelected: store.selectedID == note.id,
                                select: { select(note) }, delete: { store.delete(note) })
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .overlayScroller()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                .stroke(Theme.Colors.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            if let note = store.selectedNote {
                ZStack(alignment: .topLeading) {
                    NoteMarkdownEditor(
                        text: selectedContent,
                        tint: note.tint,
                        onContentHeightChange: updateEditorHeight,
                        onNavigate: navigate)
                    if note.content.isEmpty {
                        // An empty note opens on the moment it was opened — a date line is usually
                        // the first thing typed anyway, and it beats a nag to start writing.
                        Text(placeholderStamp.formatted(date: .long, time: .shortened))
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.xxl)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: editorHeight)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var editorToolbar: some View {
        ZStack {
            // Centred against the full toolbar width rather than against its own measured width, so
            // the dots cannot re-centre when anything beside them changes.
            NotePagination(
                notes: store.notes, selectedID: store.selectedID,
                open: { if !showsNoteList { toggleNoteList() } }
            )
            .padding(.horizontal, Theme.Size.noteToolbarTitleInset)
            .frame(maxWidth: .infinity)

            HStack(spacing: Theme.Spacing.sm) {
                // The window hides its standard buttons, so close is a toolbar control like the rest.
                NoteGlassButton(systemImage: "xmark", help: "Close Notes", action: close)
                    .keyboardShortcut("w", modifiers: .command)

                Spacer(minLength: 0)

                NoteTintPicker(
                    tint: store.selectedNote?.tint, transparency: store.windowTransparency,
                    select: setTint, setTransparency: store.setWindowTransparency)

                NoteGlassButton(
                    systemImage: "note.text",
                    help: showsNoteList ? "Hide Notes List" : "Show Notes List",
                    action: toggleNoteList)

                NoteGlassButton(systemImage: "plus", help: "New Note") { createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(
            maxWidth: .infinity, minHeight: Theme.Size.noteToolbarHeight,
            maxHeight: Theme.Size.noteToolbarHeight)
        // Belt and braces: the list toggle must never animate this row, whatever transaction is live.
        .animation(nil, value: showsNoteList)
    }

    private var selectedContent: Binding<String> {
        Binding(
            get: { store.selectedNote?.content ?? "" },
            set: { store.updateSelectedContent($0) })
    }

    private var editorWindowHeight: CGFloat {
        NoteEditorMetrics.windowHeight(forEditorHeight: editorHeight)
    }

    private func createNote() {
        query = ""
        store.createNote()
        editorHeight = NoteEditorMetrics.estimatedEditorHeight(for: "")
        closeNoteList()
    }

    private func setTint(_ tint: NoteTint?) {
        guard let id = store.selectedID else { return }
        store.setTint(tint, for: id)
    }

    private func select(_ note: SpotterNote) {
        store.select(note)
        editorHeight = NoteEditorMetrics.estimatedEditorHeight(for: note.content)
        closeNoteList()
    }

    private func navigate(_ direction: NoteNavigationDirection) {
        guard let note = store.selectAdjacent(direction) else { return }
        editorHeight = NoteEditorMetrics.estimatedEditorHeight(for: note.content)
        resizeHeight(NoteEditorMetrics.windowHeight(forEditorHeight: editorHeight), true)
    }

    private func updateEditorHeight(_ height: CGFloat) {
        guard abs(editorHeight - height) > 0.5 else { return }
        editorHeight = height
        let contentHeight = NoteEditorMetrics.windowHeight(forEditorHeight: height)
        resizeHeight(
            showsNoteList ? max(contentHeight, Theme.Size.noteListWindowHeight) : contentHeight,
            false)
    }

    private func toggleNoteList() {
        if showsNoteList {
            closeNoteList()
        } else {
            showsNoteList = true
            resizeHeight(max(editorWindowHeight, Theme.Size.noteListWindowHeight), true)
            DispatchQueue.main.async { searchIsFocused = true }
        }
    }

    private func closeNoteList() {
        showsNoteList = false
        searchIsFocused = false
        resizeHeight(editorWindowHeight, true)
    }
}

/// One Liquid Glass toolbar control: an interactive glass circle holding a single glyph.
struct NoteGlassButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(
                    width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(help)
    }
}

private struct NoteListRow: View {
    let note: SpotterNote
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if let tint = note.tint {
                            Circle()
                                .fill(Theme.Colors.noteTintAccent(tint))
                                .frame(width: Theme.Size.noteTintDot, height: Theme.Size.noteTintDot)
                        }
                        Text(note.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hovering || isSelected {
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Note")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isSelected ? Theme.Colors.selection : hovering ? Theme.Colors.rowHover : .clear)
        )
        .contentShape(Rectangle())
        .contextMenu { Button("Delete Note", role: .destructive, action: delete) }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    private var metadata: String {
        let characters = note.content.count
        let count = "\(characters) \(characters == 1 ? "Character" : "Characters")"
        if isSelected { return "Current · \(count)" }
        return "Updated \(note.updatedAt.formatted(.relative(presentation: .named))) · \(count)"
    }
}
