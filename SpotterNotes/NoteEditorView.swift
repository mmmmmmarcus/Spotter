import SwiftUI

/// One open Note: the editor over its tint, with the Note's colour and deletion in the toolbar.
struct NoteEditorView: View {
    let model: NotesModel
    @ObservedObject var store: NoteStore
    let note: SpotterNote
    let delete: () -> Void

    var body: some View {
        NoteTextEditor(
            text: Binding(get: { note.content }, set: { model.update($0, for: note.id) }),
            noteID: note.id, tint: note.tint, focusRequest: store.editorFocusRequest
        )
        .background {
            if let tint = note.tint {
                Color(uiColor: NotesTheme.Colors.tintWash(tint)).ignoresSafeArea()
            }
        }
        // The Note's own first line is its title; a second copy in the bar would only repeat it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Note Options", systemImage: "ellipsis") {
                    Picker(
                        "Note Color", systemImage: "paintpalette",
                        selection: Binding(get: { note.tint }, set: { store.setTint($0, for: note.id) })
                    ) {
                        Text("No Color").tag(NoteTint?.none)
                        ForEach(tintChoices, id: \.self) { tint in
                            Label {
                                Text(tint.displayName)
                            } icon: {
                                Image(uiImage: swatch(for: tint))
                            }
                            .tag(NoteTint?.some(tint))
                        }
                    }
                    .pickerStyle(.menu)
                    Button("Delete Note", systemImage: "trash", role: .destructive, action: delete)
                }
            }
        }
    }

    /// A tint from the older ramp stays selectable on the Note that already carries it.
    private var tintChoices: [NoteTint] {
        guard let tint = note.tint, !NoteTint.selectable.contains(tint) else { return NoteTint.selectable }
        return NoteTint.selectable + [tint]
    }

    /// Menus draw symbols as templates; an original-mode image is what keeps each swatch its own colour.
    private func swatch(for tint: NoteTint) -> UIImage {
        UIImage(systemName: "circle.fill")?
            .withTintColor(NotesTheme.Colors.tintAccent(tint), renderingMode: .alwaysOriginal) ?? UIImage()
    }
}
