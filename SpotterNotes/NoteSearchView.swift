import SwiftUI

/// Finding a Note by its text, which a strip of markers cannot do. Results appear only for a query: this is a search, never a second way to browse.
struct NoteSearchView: View {
    @ObservedObject var store: NoteStore

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isFieldActive = true

    var body: some View {
        NavigationStack {
            List(matches) { note in
                Button {
                    store.select(note)
                    dismiss()
                } label: {
                    NoteSearchRow(note: note)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Search Notes", systemImage: "magnifyingglass",
                        description: Text("Find a Note by its title or its text."))
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query, isPresented: $isFieldActive,
                placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Notes"
            )
            // The field's own Cancel is the way out: a sheet left behind with no field would be an empty screen.
            .onChange(of: isFieldActive) { _, isActive in
                if !isActive { dismiss() }
            }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: [SpotterNote] {
        guard !trimmedQuery.isEmpty else { return [] }
        return store.notes.filter { $0.content.localizedCaseInsensitiveContains(trimmedQuery) }
    }
}

private struct NoteSearchRow: View {
    let note: SpotterNote

    var body: some View {
        HStack(spacing: NotesTheme.Spacing.xl) {
            NoteMarker(note: note, isSelected: true)
                .frame(width: NotesTheme.Size.markerEmoji)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
