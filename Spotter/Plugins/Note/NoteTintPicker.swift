import SwiftUI

/// The toolbar's appearance control: the note's tint and the window's transparency, the two things
/// that decide how a note looks, in the one place the user is already looking at the note. The
/// brush keeps its own color — a control that changed color with the note would read as a swatch,
/// and there would be nothing left to point at when the note has no tint at all.
struct NoteTintPicker: View {
    let tint: NoteTint?
    let transparency: Double
    let select: (NoteTint?) -> Void
    let setTransparency: (Double) -> Void
    @State private var showsPanel = false

    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Size.noteTintSwatch), spacing: Theme.Spacing.md),
        count: 5)

    var body: some View {
        Button { showsPanel.toggle() } label: {
            Image(systemName: "paintbrush.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Theme.Size.noteGlassButton, height: Theme.Size.noteGlassButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Note Color")
        .popover(isPresented: $showsPanel, arrowEdge: .bottom) {
            NoteTintPanel(
                tint: tint, transparency: transparency, select: choose,
                setTransparency: setTransparency)
        }
    }

    private func choose(_ candidate: NoteTint?) {
        select(candidate)
        showsPanel = false
    }
}

/// The panel behind the brush: the ramp, and the window's transparency under it.
struct NoteTintPanel: View {
    let tint: NoteTint?
    let transparency: Double
    let select: (NoteTint?) -> Void
    let setTransparency: (Double) -> Void

    private let columns = Array(
        repeating: GridItem(.fixed(Theme.Size.noteTintSwatch), spacing: Theme.Spacing.md),
        count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(NoteTint.allCases, id: \.self) { candidate in
                    button(for: candidate)
                }
                button(for: nil)
            }

            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("Window Transparency")
                        .font(.callout)
                    Spacer(minLength: Theme.Spacing.xl)
                    Text(transparency.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // The same stored value Settings edits, so the two are never out of step.
                Slider(
                    value: Binding(get: { transparency }, set: setTransparency),
                    in: 0...NoteStore.maximumWindowTransparency,
                    step: 0.05)
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
                    .foregroundStyle(candidate == nil ? Theme.Colors.textSecondary : .white)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// The toolbar's page dots: one per note, newest first, the current one filled. It replaces the note
/// title because the title is already the first line of the note directly under it — what the header
/// can say that the page cannot is *where in the stack you are*. The whole strip opens the list.
struct NotePagination: View {
    let notes: [SpotterNote]
    let selectedID: UUID?
    let open: () -> Void

    /// Past this many the dots stop being countable, so the strip slides around the current note.
    private static let visibleDots = 9

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(window, id: \.id) { note in
                    let isSelected = note.id == selectedID
                    Circle()
                        .fill(color(for: note, isSelected: isSelected))
                        .frame(
                            width: isSelected ? Theme.Size.noteDotSelected : Theme.Size.noteDot,
                            height: isSelected ? Theme.Size.noteDotSelected : Theme.Size.noteDot)
                }
            }
            .frame(height: Theme.Size.settingsRowIcon)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show Notes List")
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
        guard notes.count > Self.visibleDots else { return notes }
        let current = notes.firstIndex { $0.id == selectedID } ?? 0
        let start = min(
            max(current - Self.visibleDots / 2, 0), notes.count - Self.visibleDots)
        return Array(notes[start..<(start + Self.visibleDots)])
    }
}
