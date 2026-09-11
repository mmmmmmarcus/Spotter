import Foundation

@main
struct SettingsSearchTests {
    static func main() {
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
        }
        check(SettingsSearch.matches(" \n ", title: "General", key: "general"), "Whitespace leaves pages visible")
        check(SettingsSearch.matches("LOGIN dock", title: "General", key: "general"), "Setting labels support multiple case-insensitive terms")
        check(!SettingsSearch.matches("login banana", title: "General", key: "general"), "Every search term must match")
        check(SettingsSearch.matches("输入法", title: "General", key: "general"), "Chinese aliases locate settings")
        check(SettingsSearch.matches("location", title: "Permissions", key: "permissions"), "Location permission is searchable")
        check(SettingsSearch.matches("cafe", title: "Café", key: "future-plugin"), "Search folds diacritics")
        check(SettingsSearch.matches("Example", title: "Example", summary: "New feature", key: "future-plugin"), "A new registration is searchable without a keyword entry")
        check(SettingsSearch.matches("new feature", title: "Example", summary: "New feature", key: "future-plugin"), "Registration summaries are searchable")
        check(!SettingsSearch.matches("private-user-note", title: "Notes", key: "note"), "The index contains no user content")
        print("Settings search: 9 checks passed")
    }
}
