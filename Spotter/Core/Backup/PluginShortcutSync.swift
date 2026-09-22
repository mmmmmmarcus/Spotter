import Foundation

enum PluginShortcutSync {
    static func replacementIDs(knownActionIDs: [String]?, bindingIDs: [String]?) -> Set<String> {
        guard let bindingIDs else { return [] }
        // An older writer cannot distinguish an unknown action from an intentionally unbound one.
        return Set(knownActionIDs ?? []).union(bindingIDs)
    }
}
