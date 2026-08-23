import Foundation

/// Built-in launcher actions surfaced alongside user-authored commands, with dispatch in `AppCore.runCommand`.
enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case checkForUpdates = "command:check-for-updates"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case settings = "command:settings"
    case about = "command:about"
    case version = "command:version"
    case quitAllApps = "command:quit-all-apps"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .checkForUpdates: return "Check for Updates"
        case .exportSettings: return "Export Settings"
        case .importSettings: return "Import Settings"
        case .importFromRaycast: return "Import from Raycast"
        case .settings: return "Settings"
        case .about: return "About Spotter"
        case .version: return "Spotter Version"
        case .quitAllApps: return "Quit All Applications"
        case .quit: return "Quit Spotter"
        }
    }

    /// The `command:` prefix is entry-list grammar, not identity; the bare slug is what a shortcut key is built from.
    var slug: String { String(rawValue.dropFirst("command:".count)) }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .checkForUpdates: return "arrow.down.circle"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .version: return "number"
        case .quitAllApps: return "xmark.circle"
        case .quit: return "power"
        }
    }
}
