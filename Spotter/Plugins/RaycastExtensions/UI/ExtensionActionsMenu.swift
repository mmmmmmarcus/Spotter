import AppKit
import SwiftUI

@MainActor
enum ExtensionActionsMenu {
    /// What the panel belongs to: the selected row, or the screen when the selection has outrun it.
    static func header(screen: ExtensionScreen, selection: Int) -> String? {
        // A form's rows are its fields, and the panel acts on the form rather than on one field.
        guard screen.kind != .form, screen.items.indices.contains(selection) else {
            return screen.navigationTitle
        }
        return screen.items[selection].node.string("title")
    }

    /// Rows carry a resolved `ExtensionImage`; resolving per ↑/↓ would probe symbols on main.
    static func rows(_ actions: [ExtensionAction], assetsPath: String?) -> [ExtensionActionItem] {
        actions.map { action in
            ExtensionActionItem(
                title: action.title,
                icon: ExtensionImage.actionIcon(
                    action.iconValue, assetsPath: assetsPath,
                    // Read rather than injected: a panel is rebuilt each time it opens.
                    isDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                    isDestructive: action.isDestructive),
                shortcut: action.shortcutCaps?.joined(),
                isDestructive: action.isDestructive,
                startsSection: action.startsSection)
        }
    }
}
