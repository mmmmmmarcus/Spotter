import Combine
import Foundation

@MainActor
final class TextReplacementStore: ObservableObject {
    @Published private(set) var prefix: String
    @Published private(set) var rules: [TextReplacementRule]

    var onChange: (@MainActor (String, [TextReplacementRule]) -> Void)?

    private let defaults: UserDefaults
    private static let prefixKey = "text-replacement.prefix"
    private static let rulesKey = "text-replacement.rules"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        prefix = Self.loadPrefix(from: defaults, key: Self.prefixKey)
        rules = Self.loadRules(from: defaults, key: Self.rulesKey)
    }

    func setPrefix(_ value: String) throws {
        let normalized = try TextReplacementValidator.normalizedPrefix(value)
        guard normalized != prefix else { return }
        prefix = normalized
        persist()
    }

    func add(_ rule: TextReplacementRule) throws {
        let normalized = try TextReplacementValidator.normalizedRule(rule, among: rules)
        rules.append(normalized)
        persist()
    }

    func update(_ rule: TextReplacementRule) throws {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let normalized = try TextReplacementValidator.normalizedRule(
            rule, among: rules, excluding: rule.id)
        rules[index] = normalized
        persist()
    }

    func delete(id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules.remove(at: index)
        persist()
    }

    private func persist() {
        defaults.set(prefix, forKey: Self.prefixKey)
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Self.rulesKey)
        }
        onChange?(prefix, rules)
    }

    private static func loadPrefix(from defaults: UserDefaults, key: String) -> String {
        guard let stored = defaults.string(forKey: key),
            let prefix = try? TextReplacementValidator.normalizedPrefix(stored)
        else { return TextReplacementValidator.defaultPrefix }
        return prefix
    }

    private static func loadRules(from defaults: UserDefaults, key: String) -> [TextReplacementRule] {
        guard let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([TextReplacementRule].self, from: data)
        else { return [] }

        var accepted: [TextReplacementRule] = []
        for rule in decoded {
            if let normalized = try? TextReplacementValidator.normalizedRule(rule, among: accepted) {
                accepted.append(normalized)
            }
        }
        return accepted
    }
}
