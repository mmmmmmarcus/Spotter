import SwiftUI

/// The whole app on iPhone and iPad alike: the open Note under a top bar whose marker strip switches between Notes. There is no list.
struct NotesRootView: View {
    let model: NotesModel
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteFolderSyncManager

    @State private var noteToDelete: SpotterNote?
    @State private var isChoosingFolder = false
    @State private var isShowingSync = false
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SyncBanner(
                    sync: sync, chooseFolder: { isChoosingFolder = true }, showSync: { isShowingSync = true })
                if let note = store.selectedNote {
                    // One editor serves every Note, so a switch replaces its document in place.
                    NoteTextEditor(
                        text: Binding(get: { note.content }, set: { model.update($0, for: note.id) }),
                        noteID: note.id, tint: note.tint, focusRequest: store.editorFocusRequest,
                        onNavigate: { store.selectAdjacent($0) })
                } else {
                    ContentUnavailableView {
                        Label("No Notes", systemImage: "note.text")
                    } description: {
                        Text("Create a note to start writing.")
                    } actions: {
                        Button("New Note") { model.createNote() }
                    }
                }
            }
            .background {
                // The open Note's tint washes the whole screen, bars included.
                if let tint = store.selectedNote?.tint {
                    Color(uiColor: NotesTheme.Colors.tintWash(tint)).ignoresSafeArea()
                }
            }
            // A Note's first line is its title, and the strip already says which Note is open.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NoteMarkerStrip(notes: store.notes, selectedID: store.selectedID, select: store.select)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("New Note", systemImage: "square.and.pencil") { model.createNote() }
                    NoteBarMenu(
                        store: store, sync: sync, delete: { noteToDelete = $0 },
                        showSync: { isShowingSync = true }, showSearch: { isSearching = true })
                }
            }
        }
        .onChange(of: store.selectedID) { _, open in
            model.sweepEmptyNotes(keeping: open)
        }
        .alert(
            "Delete Note?", isPresented: Binding(get: { noteToDelete != nil }, set: { if !$0 { noteToDelete = nil } }),
            presenting: noteToDelete
        ) { note in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { store.delete(note) }
        } message: { note in
            Text(deletionMessage(for: note))
        }
        .notesFolderPicker(isPresented: $isChoosingFolder, sync: sync)
        .sheet(isPresented: $isShowingSync) {
            SyncSettingsView(sync: sync)
        }
        .sheet(isPresented: $isSearching) {
            NoteSearchView(store: store)
        }
    }

    private func deletionMessage(for note: SpotterNote) -> String {
        let name = "“\(note.displayTitle)”"
        return sync.isEnabled
            ? "\(name) will be deleted on every device that syncs with this folder."
            : "\(name) will be deleted."
    }
}
