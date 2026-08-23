import Foundation

@main
struct CommandsTests {
    static func main() {
        var failures = 0

        func check(_ message: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(message)")
            } else {
                failures += 1
                print("FAIL  \(message)")
            }
        }

        check("thirty built-in commands", SystemCommandCatalog.all.count == 30)
        check(
            "stable unique launcher ids",
            Set(SystemCommandCatalog.all.map(\.entryID)).count == SystemCommandCatalog.all.count)

        let destructive = Set(
            SystemCommandCatalog.all.filter { $0.confirmation == .required }.map(\.id))
        check(
            "destructive commands remain mandatory",
            destructive == [.restart, .shutDown, .logOut, .emptyTrash, .quitAllApps])

        for command in SystemCommandCatalog.all {
            let action = PluginActionKey.systemCommand(command.id)
            check("\(command.name) belongs to Commands", action.pluginID == .commands)
            check(
                "\(command.name) keeps legacy shortcut storage",
                action.defaultsKey
                    == "KeyboardShortcuts_plugin.system-commands.\(command.id.rawValue)")
        }

        // The slug keys a persisted shortcut, so a collision would silently make two built-in
        // commands share one binding, and a change would unbind whatever the user had set.
        check(
            "every built-in command has a slug",
            CommandID.allCases.allSatisfy { !$0.slug.isEmpty && !$0.slug.contains("command:") })
        check(
            "built-in command slugs are unique",
            Set(CommandID.allCases.map(\.slug)).count == CommandID.allCases.count)
        check(
            "every built-in command id keeps the entry-list prefix",
            CommandID.allCases.allSatisfy { $0.rawValue == "command:" + $0.slug })
        check(
            "every built-in command names itself",
            CommandID.allCases.allSatisfy { !$0.name.isEmpty && !$0.sfSymbol.isEmpty })

        // A launcher command that reuses a plugin's own shortcut action is what makes one binding
        // serve the plugin's Settings pane, its Commands row and its launcher keycap at once. These
        // two predate the generic `standard(pluginID:actionID:title:)` key, so their storage keys
        // are the bare legacy names — renaming one unbinds every existing shortcut and backup.
        check(
            "Clipboard History keeps its legacy binding",
            PluginActionKey.openClipboard.defaultsKey == "KeyboardShortcuts_toggleClipboard")
        check(
            "Clipboard History belongs to Clipboard",
            PluginActionKey.openClipboard.pluginID == .clipboard)
        check(
            "Emoji & Symbols keeps its legacy binding",
            PluginActionKey.openEmoji.defaultsKey == "KeyboardShortcuts_toggleEmoji")
        check(
            "Emoji & Symbols belongs to Emoji", PluginActionKey.openEmoji.pluginID == .emoji)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
