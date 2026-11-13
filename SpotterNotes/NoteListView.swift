import SwiftUI

/// The Notes list, in the order the store keeps: most recently edited first.
struct NoteListView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteFolderSyncManager
    @Binding var selection: UUID?
    let delete: (SpotterNote) -> Void
    let chooseFolder: () -> Void

    @State private var search = ""

    var body: some View {
        List(selection: $selection) {
            SyncNotice(sync: sync, chooseFolder: chooseFolder)
            if visibleNotes.isEmpty { emptyState }
            ForEach(visibleNotes) { note in
                NoteRow(note: note)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Not a destructive-role button: that removes the row before the confirmation has been answered.
                        Button("Delete", systemImage: "trash") { delete(note) }
                            .tint(.red)
                    }
            }
        }
        .searchable(text: $search, prompt: "Search Notes")
    }

    /// A row rather than an overlay, which would sit on top of the sync notice and swallow its button.
    private var emptyState: some View {
        Group {
            if search.isEmpty {
                ContentUnavailableView(
                    "No Notes", systemImage: "note.text", description: Text("Tap the pencil to write one."))
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
        .listRowBackground(Color.clear)
        .selectionDisabled()
    }

    private var visibleNotes: [SpotterNote] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.notes }
        return store.notes.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }
}

private struct NoteRow: View {
    let note: SpotterNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NotesTheme.Spacing.xl) {
            marker
                .frame(width: NotesTheme.Size.listMarker)
            VStack(alignment: .leading, spacing: NotesTheme.Spacing.xs) {
                Text(note.titleWithoutEmoji)
                    .font(.headline)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: NotesTheme.Spacing.sm) {
                    Text(note.contentUpdatedAt, format: .relative(presentation: .named))
                    Text(note.excerpt)
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    /// A title's first emoji marks its Note; every other Note gets a dot in its tint.
    @ViewBuilder private var marker: some View {
        if let emoji = note.titleEmoji {
            Text(emoji)
        } else {
            Circle()
                .fill(note.tint.map { Color(uiColor: NotesTheme.Colors.tintAccent($0)) } ?? Color(uiColor: .tertiaryLabel))
                .frame(width: NotesTheme.Size.tintDot, height: NotesTheme.Size.tintDot)
        }
    }
}
