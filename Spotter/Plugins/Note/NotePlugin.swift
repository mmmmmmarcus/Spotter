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
            defaultEnabled: true,
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
            onEnable: { [weak core] in
                core?.noteSync.start()
            },
            onDisable: { [weak core] in
                guard let core else { return }
                core.closePluginWindow(id: "notes")
                core.noteSync.stop()
                Task { await core.notes.flush() }
            },
            settingsView: {
                AnyView(NoteSettingsView(store: core.notes, sync: core.noteSync))
            })
    }
}

extension AppCore {
    func openNotes(creatingNewNote: Bool = false) {
        guard plugins.isEnabled(.note) else { return }
        // Open Notes is a toggle — the window floats over everything, so the shortcut that summoned
        // it is the obvious way to put it away. New Note always opens, since it has a note to show.
        if !creatingNewNote, isPluginWindowShowing(id: "notes") {
            closePluginWindow(id: "notes")
            return
        }
        if creatingNewNote { notes.createNote() }
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        let initialEditorHeight = NoteEditorMetrics.estimatedEditorHeight(
            for: notes.selectedNote?.content ?? "")
        showPluginWindow(
            id: "notes", title: "Notes",
            size: CGSize(
                width: Theme.Size.noteWindowWidth,
                height: NoteEditorMetrics.windowHeight(forEditorHeight: initialEditorHeight)),
            resizable: true, floating: true, transparent: true,
            minimumSize: CGSize(
                width: Theme.Size.noteWindowMinimumWidth,
                height: NoteEditorMetrics.windowHeight(
                    forEditorHeight: NoteEditorMetrics.minimumEditorHeight)),
            closeButtonOnly: true, contentExtendsIntoTitleBar: true
        ) {
            NoteView(
                store: notes,
                resizeHeight: { [weak self] height, animated in
                    self?.resizePluginWindow(id: "notes", height: height, animated: animated)
                })
        }
    }
}
