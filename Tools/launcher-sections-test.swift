// Compile with `Spotter/Core/LauncherSections.swift`; see docs/development.md.
import Foundation

@main
@MainActor
enum LauncherSectionsTest {
    static var failures = 0

    static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(message)")
        } else {
            failures += 1
            print("FAIL  \(message)")
        }
    }

    static func main() {
        check(
            "a never-saved order is the default order",
            LauncherSectionsEngine.order(fromRaw: nil) == LauncherSectionsEngine.defaultOrder)
        check(
            "a saved order survives round-tripping",
            LauncherSectionsEngine.order(
                fromRaw: ["commands", "favorites", "active-apps", "applications", "system-settings"])
                == [.commands, .favorites, .activeApps, .applications, .systemSettings])
        check(
            "unknown names drop and missing sections append in default order",
            LauncherSectionsEngine.order(fromRaw: ["commands", "widgets", "commands"])
                == [.commands, .favorites, .activeApps, .applications, .systemSettings])
        check(
            "duplicates collapse to the first occurrence",
            LauncherSectionsEngine.order(
                fromRaw: ["favorites", "applications", "favorites", "commands"])
                .filter { $0 == .favorites }.count == 1)

        check(
            "a never-saved hidden set hides only Active Apps",
            LauncherSectionsEngine.hidden(fromRaw: nil) == [.activeApps])
        check(
            "a saved empty hidden set means everything shows",
            LauncherSectionsEngine.hidden(fromRaw: []).isEmpty)
        check(
            "unknown hidden names drop",
            LauncherSectionsEngine.hidden(fromRaw: ["commands", "widgets"]) == [.commands])

        check(
            "every section has a distinct raw name",
            Set(LauncherSection.allCases.map(\.rawValue)).count
                == LauncherSection.allCases.count)

        if failures > 0 {
            print("\n\(failures) failure(s)")
            exit(1)
        }
        print("\nAll launcher-section checks passed")
    }
}
