import Foundation

/// A concrete model and optional reasoning effort the user chose for chat or an AI command.
struct AIModelChoice: Codable, Equatable, Sendable {
    static let defaultChat = Self(model: "local-cli/codex/gpt-6-luna", effort: "low")

    var model: String
    var effort: String?

    init(model: String, effort: String? = nil) {
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.effort = AIReasoningEffort.normalized(effort)
    }
}

/// Decode-only: Jev's Everyday / Professional / Deep Reasoning mappings, read once to migrate the chat model and category-pinned commands.
struct AILegacyRouting: Codable, Equatable, Sendable {
    static let defaultsKey = "openrouter.ai-routing"
    /// What a Jev-era install resolved when it never saved mappings or a chat model.
    static let shipped = Self(everydayModel: AIModelChoice.defaultChat.model,
        professionalModel: AIModelChoice.defaultChat.model, reasoningModel: AIModelChoice.defaultChat.model,
        everydayEffort: "low", professionalEffort: "medium", reasoningEffort: "xhigh")

    var everydayModel: String?
    var professionalModel: String?
    var reasoningModel: String?
    var everydayEffort: String?
    var professionalEffort: String?
    var reasoningEffort: String?

    /// The pair a category resolved to, or nil when that tier was unset (it then followed the chat model).
    func choice(for category: String) -> AIModelChoice? {
        let pair: (model: String?, effort: String?)
        switch category {
        case "everyday": pair = (everydayModel, everydayEffort)
        case "professional": pair = (professionalModel, professionalEffort)
        case "reasoning": pair = (reasoningModel, reasoningEffort)
        default: return nil
        }
        let choice = AIModelChoice(model: pair.model ?? "", effort: pair.effort)
        return choice.model.isEmpty ? nil : choice
    }
}

enum AIReasoningEffort {
    static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty, value.count <= 32, value != "default",
            value.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return value
    }

    static func supported(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(normalized).filter { seen.insert($0).inserted }
    }

    static func resolve(_ value: String?, supported: [String]) -> String? {
        guard let value = normalized(value), supported.contains(value) else { return nil }
        return value
    }

    static func title(_ value: String) -> String {
        switch value {
        case "xhigh": "Extra High"
        default: value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
