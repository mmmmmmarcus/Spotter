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
            onDisable: { [weak core] in
                guard let core else { return }
                core.closePluginWindow(id: "notes")
                Task { await core.notes.flush() }
            },
            settingsView: { AnyView(NoteSettingsView(store: core.notes)) })
    }
}

extension AppCore {
    func openNotes(creatingNewNote: Bool = false) {
        guard plugins.isEnabled(.note) else { return }
        if creatingNewNote { notes.createNote() }
        if palette.mode == .launcher { hidePalette(restoreFocus: false) }
        showPluginWindow(
            id: "notes", title: "Notes", size: CGSize(width: 760, height: 600),
            resizable: true, floating: true, minimumSize: CGSize(width: 640, height: 440)
        ) {
            NoteView(store: notes)
        }
    }
}
