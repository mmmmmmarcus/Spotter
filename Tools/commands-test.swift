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

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
