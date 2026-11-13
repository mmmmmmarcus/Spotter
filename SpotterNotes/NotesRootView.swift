import SwiftUI

/// A sidebar on iPad and a stack on iPhone: the list on one side, the open Note on the other.
struct NotesRootView: View {
    let model: NotesModel
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteFolderSyncManager

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var openNoteID: UUID?
    @State private var noteToDelete: SpotterNote?
    @State private var isChoosingFolder = false
    @State private var isShowingSync = false
    @State private var hasAppeared = false

    var body: some View {
        NavigationSplitView {
            NoteListView(
                store: store, sync: sync, selection: $openNoteID,
                delete: { noteToDelete = $0 }, chooseFolder: { isChoosingFolder = true }
            )
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sync", systemImage: syncSymbol) { isShowingSync = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Note", systemImage: "square.and.pencil") { openNoteID = model.createNote() }
                }
            }
        } detail: {
            if let note = store.notes.first(where: { $0.id == openNoteID }) {
                NoteEditorView(model: model, store: store, note: note, delete: { noteToDelete = note })
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "note.text")
            }
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            // A sidebar always has a detail beside it; a phone starts on the list instead.
            if sizeClass == .regular, let selected = store.selectedNote, !NoteEngine.isEmptyDraft(selected.content) {
                openNoteID = selected.id
            }
        }
        .onChange(of: openNoteID) { _, open in
            if let open { store.selectedID = open }
            model.sweepEmptyNotes(keeping: open)
        }
        .onChange(of: store.notes.map(\.id)) { _, ids in
            // Deleted here or by another device's tombstone: the editor closes rather than showing a Note that is gone.
            if let openNoteID, !ids.contains(openNoteID) { self.openNoteID = nil }
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
    }

    private var syncSymbol: String {
        if sync.errorMessage != nil || sync.isFolderUnavailable { return "exclamationmark.arrow.triangle.2.circlepath" }
        return sync.isEnabled ? "arrow.triangle.2.circlepath" : "folder.badge.plus"
    }

    private func deletionMessage(for note: SpotterNote) -> String {
        let name = "“\(note.title)”"
        return sync.isEnabled
            ? "\(name) will be deleted on every device that syncs with this folder."
            : "\(name) will be deleted."
    }
}
