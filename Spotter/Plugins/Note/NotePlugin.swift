import SwiftUI

extension PluginActionKey {
    static let openNotes = standard(pluginID: .note, actionID: "open", title: "Open Notes")
    static let newNote = standard(pluginID: .note, actionID: "new", title: "New Note")
}

@MainActor
enum NotePlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        let open: () -> Void = { [weak core] in core?.openNotes() }
        let create: () -> Void = { [weak core] in core?.openNotes(creatingNewNote: true) }
        return PluginRegistration(
            metadata: PluginMetadata(
                id: .note, name: "Notes",
                summary: "Capture Markdown notes and todos in an always-ready floating window.",
                systemImage: "note.text", tint: .yellow),
            shortcutActions: [
                PluginActionRegistration(key: .openNotes, perform: open),
                PluginActionRegistration(key: .newNote, perform: create),
            ],
            launcherCommands: [
                PluginCommandRegistration(
                    id: "command:notes", name: "Open Notes", systemImage: "note.text",
                    actionKey: .openNotes, perform: open),
                PluginCommandRegistration(
                    id: "command:notes:new", name: "New Note", systemImage: "square.and.pencil",
                    actionKey: .newNote, perform: create),
            ],
            dynamicLauncherCommands: { [weak core] in
                guard let core else { return [] }
                return core.notes.notes.compactMap { note in
                    guard NoteEngine.leadingH1Title(in: note.content) != nil else { return nil }
                    return PluginCommandRegistration(
                        id: "command:note:\(note.id.uuidString)", name: note.title,
                        systemImage: "note.text"
                    ) { [weak core] in core?.openNotes(noteID: note.id) }
                }
            },
            onStart: { [weak core] in
                core?.noteFolderSync.start()
            },
            settingsView: {
                AnyView(NoteSettingsView(store: core.notes, sync: core.noteFolderSync))
            })
    }
}

extension AppCore {
    func openNotes(creatingNewNote: Bool = false, noteID: UUID? = nil) {
        // Open Notes is a toggle — the window floats over everything, so the shortcut that summoned
        // it is the obvious way to put it away. New Note always opens, since it has a note to show.
        if !creatingNewNote, noteID == nil, isPluginWindowShowing(id: "notes") {
            closePluginWindow(id: "notes")
            return
        }
        if let noteID {
            guard let note = notes.notes.first(where: { $0.id == noteID }) else { return }
            notes.select(note)
        }
        if creatingNewNote { notes.createNote() }
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        notes.requestEditorFocus()
        showPluginWindow(
            id: "notes", title: "Notes",
            size: CGSize(
                width: Theme.Size.noteWindowWidth,
                height: Theme.Size.noteWindowHeight),
            resizable: true, floating: true, transparent: true,
            minimumSize: CGSize(
                width: Theme.Size.noteWindowMinimumWidth,
                height: Theme.Size.noteWindowMinimumHeight),
            hidesStandardButtons: true, contentExtendsIntoTitleBar: true,
            frameAutosaveName: "\(Bundle.main.bundleIdentifier ?? "com.spotter.app1").note-window"
        ) {
            NoteView(
                store: notes,
                close: { [weak self] in self?.closePluginWindow(id: "notes") })
        }
    }
}
