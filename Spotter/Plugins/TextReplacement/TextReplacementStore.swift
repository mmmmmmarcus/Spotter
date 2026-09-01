import Combine
import Foundation

@MainActor
final class TextReplacementStore: ObservableObject {
    @Published private(set) var prefix: String
    @Published private(set) var snippets: [Snippet]

    var onChange: (@MainActor (String, [Snippet]) -> Void)?

    private let defaults: UserDefaults
    private static let prefixKey = "text-replacement.prefix"
    // Deliberately the retired rules key: old records decode as expanding snippets in place, so nothing migrates by hand.
    private static let snippetsKey = "text-replacement.rules"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefix = Self.loadPrefix(from: defaults, key: Self.prefixKey)
        snippets = Self.loadSnippets(from: defaults, key: Self.snippetsKey)
    }

    func setPrefix(_ value: String) throws {
        let normalized = try SnippetValidator.normalizedPrefix(value)
        guard normalized != prefix else { return }
        prefix = normalized
        persist()
    }

    func add(_ snippet: Snippet) throws {
        let normalized = try SnippetValidator.normalizedSnippet(snippet, among: snippets)
        snippets.append(normalized)
        persist()
    }

    func update(_ snippet: Snippet) throws {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let normalized = try SnippetValidator.normalizedSnippet(
            snippet, among: snippets, excluding: snippet.id)
        snippets[index] = normalized
        persist()
    }

    func delete(id: UUID) {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets.remove(at: index)
        persist()
    }

    /// Settings-backup import: replace prefix and snippets wholesale, dropping anything that fails the same validation `add`/`update` enforce (a hand-edited file must not smuggle in a conflicting set).
    func replace(prefix newPrefix: String?, snippets newSnippets: [Snippet]) {
        if let newPrefix, let normalized = try? SnippetValidator.normalizedPrefix(newPrefix) {
            prefix = normalized
        }
        var accepted: [Snippet] = []
        for snippet in newSnippets {
            if let normalized = try? SnippetValidator.normalizedSnippet(snippet, among: accepted) {
                accepted.append(normalized)
            }
        }
        snippets = accepted
        persist()
    }

    private func persist() {
        defaults.set(prefix, forKey: Self.prefixKey)
        if let data = try? JSONEncoder().encode(snippets) {
            defaults.set(data, forKey: Self.snippetsKey)
        }
        onChange?(prefix, snippets)
    }

    private static func loadPrefix(from defaults: UserDefaults, key: String) -> String {
        guard let stored = defaults.string(forKey: key),
            let prefix = try? SnippetValidator.normalizedPrefix(stored)
        else { return SnippetValidator.defaultPrefix }
        return prefix
    }

    private static func loadSnippets(from defaults: UserDefaults, key: String) -> [Snippet] {
        guard let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return [] }

        var accepted: [Snippet] = []
        for snippet in decoded {
            if let normalized = try? SnippetValidator.normalizedSnippet(snippet, among: accepted) {
                accepted.append(normalized)
            }
        }
        return accepted
    }
}
