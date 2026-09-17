import SwiftUI

/// The toolbar's appearance control: the note's tint and the window's transparency — how a note
/// looks, in the one place the user is already looking at the note. The brush keeps its own
/// color — a control that changed color with the note would read as a swatch, and there would be
/// nothing left to point at when the note has no tint at all.
struct NoteTintPicker: View {
    let tint: NoteTint?
    let transparency: Double
    let select: (NoteTint?) -> Void
    let setTransparency: (Double) -> Void
    @State private var showsPanel = false

    var body: some View {
        Button { showsPanel.toggle() } label: {
            Image(systemName: "paintbrush.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Note Appearance")
        .popover(isPresented: $showsPanel, arrowEdge: .bottom) {
            NoteTintPanel(
                tint: tint, transparency: transparency, select: select,
                setTransparency: setTransparency)
        }
    }


}

/// The panel behind the brush: the tint ramp and the window's transparency.
struct NoteTintPanel: View {
    let tint: NoteTint?
    let transparency: Double
    let select: (NoteTint?) -> Void
    let setTransparency: (Double) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
        count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Appearance").font(.headline)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Note Color").font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                    button(for: nil)
                    ForEach(NoteTint.selectable, id: \.self) { button(for: $0) }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Window Transparency").font(.callout).foregroundStyle(.secondary)
                Picker("Window Transparency", selection: Binding(
                    get: { NoteTransparency.nearest(to: transparency) },
                    set: { setTransparency($0.rawValue) }
                )) {
                    ForEach(NoteTransparency.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .frame(width: Theme.Size.noteTintPanelWidth)
        .padding(Theme.Spacing.xl)
    }

    private func button(for candidate: NoteTint?) -> some View {
        Button { select(candidate) } label: {
            swatch(for: candidate)
        }
        .buttonStyle(.plain)
        .help(candidate?.displayName ?? "No Color")
    }

    private func swatch(for candidate: NoteTint?) -> some View {
        let size = Theme.Size.noteTintSwatch
        return ZStack {
            Circle()
                .fill(candidate.map(Theme.Colors.noteTintAccent) ?? Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        candidate == nil ? Theme.Colors.border : .clear, lineWidth: 1))
            if candidate == nil {
                // Nothing to show for "no color" but the absence itself, so the slash says it.
                Image(systemName: "slash.circle")
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            if candidate == tint {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// The toolbar's page markers: an Emoji from the title when it has one, otherwise the original dot.
/// They run newest first and the whole strip opens the list.
struct NotePagination: View {
    let notes: [SpotterNote]
    let selectedID: UUID?
    let open: () -> Void

    /// Seven full Emoji slots fit the toolbar's centered 216-point lane without clipping.
    private static let visibleMarkers = 7

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(window, id: \.id) { note in
                    let isSelected = note.id == selectedID
                    marker(for: note, isSelected: isSelected)
                }
            }
            .frame(height: Theme.Size.noteEmojiMarker)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show Notes List")
    }

    @ViewBuilder
    private func marker(for note: SpotterNote, isSelected: Bool) -> some View {
        if let emoji = note.titleEmoji {
            Text(emoji)
                .font(.system(size: 18))
                .opacity(isSelected ? 1 : 0.48)
                .fixedSize()
                .frame(
                    minWidth: Theme.Size.noteEmojiMarker,
                    minHeight: Theme.Size.noteEmojiMarker)
                .accessibilityLabel(note.title)
        } else {
            Circle()
                .fill(color(for: note, isSelected: isSelected))
                .frame(
                    width: isSelected ? Theme.Size.noteDotSelected : Theme.Size.noteDot,
                    height: isSelected ? Theme.Size.noteDotSelected : Theme.Size.noteDot)
                .accessibilityLabel(note.title)
        }
    }

    private func color(for note: SpotterNote, isSelected: Bool) -> Color {
        guard let tint = note.tint else {
            return isSelected ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
        }
        let accent = Theme.Colors.noteTintAccent(tint)
        return isSelected ? accent : accent.opacity(0.45)
    }

    /// The dots around the current note, so a long stack still shows where the caret is in it.
    private var window: [SpotterNote] {
        guard notes.count > Self.visibleMarkers else { return notes }
        let current = notes.firstIndex { $0.id == selectedID } ?? 0
        let start = min(
            max(current - Self.visibleMarkers / 2, 0), notes.count - Self.visibleMarkers)
        return Array(notes[start..<(start + Self.visibleMarkers)])
    }
}
