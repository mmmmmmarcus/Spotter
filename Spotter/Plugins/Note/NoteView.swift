import AppKit
import SwiftUI

struct NoteView: View {
    @ObservedObject var store: NoteStore
    let close: () -> Void
    @State private var navigationDirection: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            editorContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDisappear { store.deleteEmptyNotes() }
        .ignoresSafeArea(edges: .top)
        .background(noteSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.window, style: .continuous))
    }

    /// Everything the window is made of below the text: the frost, the scrim over it and the note's
    /// tint film. Window Transparency fades the scrim and nothing else — the frost stays at full
    /// strength so the window always reads as glass rather than as a hole cut in the screen, and the
    /// tint keeps its color so the most see-through notes are not the least identifiable. Text and
    /// controls above stay at full strength too.
    private var noteSurface: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
            Theme.Colors.panelScrim.opacity(1 - store.windowTransparency)
            tintWash
        }
    }

    @ViewBuilder private var tintWash: some View {
        if let tint = store.selectedNote?.tint {
            Theme.Colors.noteTintWash(tint)
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            if let note = store.selectedNote {
                NoteMarkdownEditor(
                    text: selectedContent,
                    noteID: note.id,
                    tint: note.tint,
                    focusRequest: store.editorFocusRequest,
                    reduceMotion: reduceMotion,
                    navigationDirection: navigationDirection,
                    onNavigate: navigate)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if NoteEngine.leadingH1Title(in: note.content) == nil {
                        Text("Title")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.xxl)
                            .allowsHitTesting(false)
                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var editorToolbar: some View {
        ZStack {
            NotePagination(notes: store.notes, selectedID: store.selectedID, select: select)
                .padding(.horizontal, Theme.Size.noteToolbarTitleInset)
                .frame(maxWidth: .infinity)

            HStack(spacing: Theme.Spacing.sm) {
                // The window hides its standard buttons, so close is a toolbar control like the rest.
                NoteGlassButton(systemImage: "xmark", help: "Close Notes", action: close)
                    .keyboardShortcut("w", modifiers: .command)

                Spacer(minLength: 0)

                NoteGlassButton(systemImage: "plus", help: "New Note", action: createNote)
                    .keyboardShortcut("n", modifiers: .command)

                NoteOptionsMenu(
                    tint: store.selectedNote?.tint, transparency: store.windowTransparency,
                    hasNote: store.selectedNote != nil, select: setTint,
                    setTransparency: store.setWindowTransparency, delete: deleteNote)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(
            maxWidth: .infinity, minHeight: Theme.Size.noteToolbarHeight,
            maxHeight: Theme.Size.noteToolbarHeight)
    }

    private var selectedContent: Binding<String> {
        Binding(
            get: { store.selectedNote?.content ?? "" },
            set: { store.updateSelectedContent($0) })
    }

    private func createNote() {
        navigationDirection = -1
        store.createNote()
        store.requestEditorFocus()
    }

    private func setTint(_ tint: NoteTint?) {
        guard let id = store.selectedID else { return }
        store.setTint(tint, for: id)
    }

    private func select(_ note: SpotterNote) {
        let current = store.notes.firstIndex { $0.id == store.selectedID } ?? 0
        let next = store.notes.firstIndex { $0.id == note.id } ?? current
        navigationDirection = next >= current ? 1 : -1
        store.select(note)
        store.requestEditorFocus()
    }

    private func navigate(_ direction: NoteNavigationDirection) {
        navigationDirection = direction == .next ? 1 : -1
        _ = store.selectAdjacent(direction)
    }

    private func deleteNote() {
        guard let note = store.selectedNote else { return }
        navigationDirection = 1
        store.delete(note)
        store.requestEditorFocus()
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
        .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
        .focusable(false)
        .accessibilityLabel(help)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(help)
    }
}
