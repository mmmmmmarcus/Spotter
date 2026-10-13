# Navigation

AppCore owns the window-navigation store and a separate, session-scoped menu search store.
On Palette presentation, the latter reads the previously focused application's menu bar off the
main actor using Accessibility. Reads stop on cancellation, after a two-second traversal budget,
at 4,000 visited nodes, or at twenty levels. No permission prompt interrupts ordinary searching.
Without Accessibility access or readable menus, regular launcher results remain available.

AppIndex holds these temporary entries separately from installed applications and registered commands.
Only typed root Palette searches include them, using the existing fuzzy scorer. Empty browsing,
Settings command lists, global shortcuts, favorites, aliases and learned ranking exclude them.
Each result carries its title, source application and menu hierarchy. Closing the Palette cancels
its read and clears the temporary results; reopening captures the new foreground application.

Activating a result captures it before dismissing the Palette, restores its application's activation,
and resolves the menu again off the main actor. Locators include child indexes and titles at every
level, including unnamed AXMenu wrappers. Changed paths and disabled items are refused rather than
falling through to another command. No menu labels or contents are persisted or sent over the network.

Switch Windows retains its existing dedicated Palette screen. Search Menu Bar Items no longer has
a launcher command or shortcut registration; old saved shortcut values are left untouched and unused.

`Tools/navigation-test.swift` covers filtering, duplicate window titles and menu locator validation.
