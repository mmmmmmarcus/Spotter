import SwiftUI

struct NoteOptionsMenu: View {
    let tint: NoteTint?
    let transparency: Double
    let hasNote: Bool
    let select: (NoteTint?) -> Void
    let setTransparency: (Double) -> Void
    let delete: () -> Void

    var body: some View {
        Menu {
            Picker("Note Color", selection: Binding(get: { tint }, set: select)) {
                Text("No Color").tag(nil as NoteTint?)
                ForEach(NoteTint.selectable, id: \.self) { color in
                    Text(color.displayName).tag(Optional(color))
                }
            }
            .pickerStyle(.menu)
            .disabled(!hasNote)
            Picker("Window Transparency", selection: Binding(
                get: { NoteTransparency.nearest(to: transparency) },
                set: { setTransparency($0.rawValue) }
            )) {
                ForEach(NoteTransparency.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)
            Divider()
            Button("Delete Note", systemImage: "trash", role: .destructive, action: delete)
                .disabled(!hasNote)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
        .focusable(false)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Note Options")
        .accessibilityLabel("Note Options")
    }
}

struct NotePagination: View {
    let notes: [SpotterNote]
    let selectedID: UUID?
    let select: (SpotterNote) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(notes) { note in
                            Button { select(note) } label: {
                                marker(for: note, isSelected: note.id == selectedID)
                                    .frame(width: Theme.Size.noteEmojiMarker, height: Theme.Size.noteEmojiMarker)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help(note.title)
                            .accessibilityLabel(note.title)
                            .accessibilityAddTraits(note.id == selectedID ? .isSelected : [])
                            .id(note.id)
                        }
                    }
                    .frame(minWidth: geometry.size.width)
                }
                .scrollIndicators(.hidden)
                .onAppear { if let selectedID { proxy.scrollTo(selectedID, anchor: .center) } }
                .onChange(of: notes.map(\.id)) {
                    if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                }
                .onChange(of: selectedID) {
                    if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                }
            }
        }
        .frame(height: Theme.Size.noteEmojiMarker)
    }

    @ViewBuilder
    private func marker(for note: SpotterNote, isSelected: Bool) -> some View {
        if let emoji = note.titleEmoji {
            Text(emoji)
                .font(.system(size: Theme.Size.noteEmojiFont))
                .opacity(isSelected ? 1 : 0.48)
                .fixedSize()
        } else {
            Circle()
                .fill(color(for: note, isSelected: isSelected))
                .frame(
                    width: isSelected ? Theme.Size.noteDotSelected : Theme.Size.noteDot,
                    height: isSelected ? Theme.Size.noteDotSelected : Theme.Size.noteDot)
        }
    }

    private func color(for note: SpotterNote, isSelected: Bool) -> Color {
        guard let tint = note.tint else {
            return isSelected ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
        }
        let accent = Theme.Colors.noteTintAccent(tint)
        return isSelected ? accent : accent.opacity(0.45)
    }
}
