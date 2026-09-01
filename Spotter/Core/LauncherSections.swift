import Foundation

/// The empty-query launcher's browse sections, orderable and individually hideable in Settings.
/// Hiding a section hides it from browsing only — search still matches everything, and hiding
/// Favorites returns its apps to the Applications pool rather than losing them.
enum LauncherSection: String, CaseIterable, Sendable {
    case favorites
    case activeApps = "active-apps"
    case applications
    case systemSettings = "system-settings"
    case commands

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .activeApps: "Active Apps"
        case .applications: "Applications"
        case .systemSettings: "System Settings"
        case .commands: "Commands"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .favorites: "Apps you starred, pinned above everything else."
        case .activeApps: "Running apps, with live CPU and memory usage."
        case .applications: "Every installed application."
        case .systemSettings: "System Settings panes."
        case .commands: "Built-in and plugin commands."
        }
    }

    var systemImage: String {
        switch self {
        case .favorites: "star"
        case .activeApps: "gauge.with.needle"
        case .applications: "square.grid.2x2"
        case .systemSettings: "gearshape"
        case .commands: "command"
        }
    }
}

/// One rendered browse section: its header title and how many of the flat results it owns.
struct LauncherSectionSlice: Equatable, Sendable {
    let title: String
    let count: Int
}

/// Pure order/visibility resolution for the browse sections, mirroring the widget-order shape:
/// whatever was saved is repaired, so a new section needs no migration and a removed one drops out.
enum LauncherSectionsEngine {
    static let defaultOrder: [LauncherSection] = [
        .favorites, .activeApps, .applications, .systemSettings, .commands,
    ]

    /// Active Apps ships hidden: sampling live process usage is a choice, not a default.
    static let defaultHidden: [LauncherSection] = [.activeApps]

    /// Unknown names drop, duplicates collapse, missing sections append in default order.
    static func order(fromRaw raw: [String]?) -> [LauncherSection] {
        var seen = Set<LauncherSection>()
        var result: [LauncherSection] = []
        for name in raw ?? [] {
            guard let section = LauncherSection(rawValue: name), seen.insert(section).inserted
            else { continue }
            result.append(section)
        }
        for section in defaultOrder where seen.insert(section).inserted {
            result.append(section)
        }
        return result
    }

    /// A nil (never saved) seeds the default; a saved empty list is a user who enabled everything.
    static func hidden(fromRaw raw: [String]?) -> Set<LauncherSection> {
        guard let raw else { return Set(defaultHidden) }
        return Set(raw.compactMap(LauncherSection.init(rawValue:)))
    }
}
