import SwiftUI

/// One tappable marker per Note in the store's order, newest first, as in the Mac's toolbar: a title's first Emoji, or a dot in the Note's tint.
struct NoteMarkerStrip: View {
    let notes: [SpotterNote]
    let selectedID: UUID?
    let select: (SpotterNote) -> Void

    var body: some View {
        // A strip that fits takes only its own width, which is what lets the bar centre it; one that does not scrolls.
        ViewThatFits(in: .horizontal) {
            markers
            ScrollViewReader { proxy in
                ScrollView(.horizontal) { markers }
                    .scrollIndicators(.hidden)
                    .onAppear { if let selectedID { proxy.scrollTo(selectedID, anchor: .center) } }
                    // An edit moves its Note to the front, so the order is watched as well as the selection.
                    .onChange(of: notes.map(\.id)) { reveal(with: proxy) }
                    .onChange(of: selectedID) { reveal(with: proxy) }
            }
        }
        .frame(height: NotesTheme.Size.markerHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notes")
    }

    private var markers: some View {
        HStack(spacing: 0) {
            ForEach(notes) { note in
                Button {
                    select(note)
                } label: {
                    NoteMarker(note: note, isSelected: note.id == selectedID)
                        .frame(width: NotesTheme.Size.markerWidth, height: NotesTheme.Size.markerHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.displayTitle)
                .accessibilityAddTraits(note.id == selectedID ? .isSelected : [])
                .id(note.id)
            }
        }
    }

    private func reveal(with proxy: ScrollViewProxy) {
        guard let selectedID else { return }
        withAnimation { proxy.scrollTo(selectedID, anchor: .center) }
    }
}

/// What stands for a Note wherever one is shown small. Selection changes opacity only on an Emoji; a dot also grows, as the Mac's does.
struct NoteMarker: View {
    let note: SpotterNote
    let isSelected: Bool

    var body: some View {
        if let emoji = note.titleEmoji {
            Text(emoji)
                .font(.system(size: NotesTheme.Size.markerEmoji))
                .opacity(isSelected ? 1 : NotesTheme.Opacity.markerDimmed)
                .fixedSize()
        } else {
            let size = isSelected ? NotesTheme.Size.markerDotSelected : NotesTheme.Size.markerDot
            Circle()
                .fill(Color(uiColor: NotesTheme.Colors.markerDot(note.tint, isSelected: isSelected)))
                .frame(width: size, height: size)
        }
    }
}

/// The top bar's menu: the open Note's colour and deletion, and the ways into Search and Sync.
struct NoteBarMenu: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var sync: NoteFolderSyncManager
    let delete: (SpotterNote) -> Void
    let showSync: () -> Void
    let showSearch: () -> Void

    var body: some View {
        Menu("Note Options", systemImage: "ellipsis") {
            if let note = store.selectedNote {
                Picker(
                    "Note Color", systemImage: "paintpalette",
                    selection: Binding(get: { note.tint }, set: { store.setTint($0, for: note.id) })
                ) {
                    Text("No Color").tag(NoteTint?.none)
                    ForEach(tintChoices(for: note), id: \.self) { tint in
                        Label {
                            Text(tint.displayName)
                        } icon: {
                            Image(uiImage: swatch(for: tint))
                        }
                        .tag(NoteTint?.some(tint))
                    }
                }
                .pickerStyle(.menu)
            }
            Section {
                Button("Search Notes", systemImage: "magnifyingglass", action: showSearch)
                Button(action: showSync) {
                    Text("Sync")
                    Text(sync.statusText)
                    Image(systemName: syncSymbol)
                }
            }
            if let note = store.selectedNote {
                Section {
                    Button("Delete Note", systemImage: "trash", role: .destructive) { delete(note) }
                }
            }
        }
    }

    private var syncSymbol: String {
        if sync.errorMessage != nil || sync.isFolderUnavailable { return "exclamationmark.arrow.triangle.2.circlepath" }
        return sync.isEnabled ? "arrow.triangle.2.circlepath" : "folder.badge.plus"
    }

    /// A tint from the older ramp stays selectable on the Note that already carries it.
    private func tintChoices(for note: SpotterNote) -> [NoteTint] {
        guard let tint = note.tint, !NoteTint.selectable.contains(tint) else { return NoteTint.selectable }
        return NoteTint.selectable + [tint]
    }

    /// Menus draw symbols as templates; an original-mode image is what keeps each swatch its own colour.
    private func swatch(for tint: NoteTint) -> UIImage {
        UIImage(systemName: "circle.fill")?
            .withTintColor(NotesTheme.Colors.tintAccent(tint), renderingMode: .alwaysOriginal) ?? UIImage()
    }
}
