import Combine
import Foundation

/// The saved AI commands: the two Spotter ships plus whatever the user adds. Foundation + Combine
/// only, so `Tools/ai-chat-test.swift` compiles it beside the pure record it stores.
@MainActor
final class AICommandStore: ObservableObject {
    private static let defaultsKey = "ai-commands"
    /// One release stored a single shared model for every selected-text action.
    private static let sharedLegacyModelKey = "openrouter.model"

    private let defaults: UserDefaults
    @Published private(set) var commands: [AICommand]
    var onChange: (([AICommand]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([AICommand].self, from: $0) }
        // The seed is read every launch, not only the first: it only ever fills in a built-in the
        // stored list is missing, so it doubles as the repair path for a truncated file.
        commands = AICommandEngine.normalized(
            decoded ?? [], seed: Self.legacySeed(from: defaults))
        if commands != decoded { persist() }
    }

    func command(id: UUID) -> AICommand? {
        commands.first { $0.id == id }
    }

    func command(_ builtIn: AIBuiltInCommand) -> AICommand? {
        command(id: builtIn.id)
    }

    func command(entryID: String) -> AICommand? {
        AICommand.id(fromEntryID: entryID).flatMap(command)
    }

    @discardableResult
    func add(_ draft: AICommand) throws -> AICommand {
        let value = try validated(draft)
        commit(commands + [value])
        return value
    }

    func update(_ draft: AICommand) throws {
        guard let index = commands.firstIndex(where: { $0.id == draft.id }) else { return }
        let value = try validated(draft)
        var updated = commands
        updated[index] = value
        commit(updated)
    }

    /// A built-in is never removed — its identity is referenced by bindings, backups and this build's
    /// own documentation. `reset` is its delete.
    @discardableResult
    func remove(id: UUID) -> AICommand? {
        guard let index = commands.firstIndex(where: { $0.id == id }),
            !commands[index].isBuiltIn
        else { return nil }
        var updated = commands
        let removed = updated.remove(at: index)
        commit(updated)
        return removed
    }

    func reset(_ builtIn: AIBuiltInCommand) {
        guard let index = commands.firstIndex(where: { $0.id == builtIn.id }) else { return }
        var updated = commands
        updated[index] = AICommand.makeBuiltIn(builtIn)
        commit(updated)
    }

    func setPrompt(_ prompt: String, for id: UUID) {
        guard var command = command(id: id) else { return }
        command.prompt = prompt
        try? update(command)
    }

    func setModel(_ model: String?, for id: UUID) {
        guard var command = command(id: id) else { return }
        command.model = model
        try? update(command)
    }

    /// Replaces the complete set during backup import and settings sync, repairing whatever the file
    /// carried rather than trusting it.
    @discardableResult
    func replace(with newCommands: [AICommand]) -> Int {
        let updated = AICommandEngine.normalized(newCommands)
        commit(updated)
        return updated.count
    }

    private func validated(_ draft: AICommand) throws -> AICommand {
        var value = draft
        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = draft.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.model?.isEmpty == true { value.model = nil }
        // A built-in's name is Spotter's; only its prompt, model and shortcut are the user's.
        if let builtIn = value.builtIn { value.name = builtIn.name }
        guard !value.name.isEmpty else { throw AICommandValidationError.emptyName }
        guard !value.prompt.isEmpty else { throw AICommandValidationError.emptyPrompt }
        guard !value.name.contains("\0"), !value.prompt.contains("\0") else {
            throw AICommandValidationError.invalidCharacter
        }
        guard
            !commands.contains(where: {
                $0.id != value.id
                    && $0.name.compare(value.name, options: .caseInsensitive) == .orderedSame
            })
        else { throw AICommandValidationError.duplicateName }
        return value
    }

    private func commit(_ updated: [AICommand]) {
        guard updated != commands else { return }
        commands = updated
        persist()
        onChange?(updated)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func legacySeed(from defaults: UserDefaults) -> AICommandSeed {
        var seed = AICommandSeed()
        for kind in AIBuiltInCommand.allCases {
            if let prompt = defaults.string(forKey: kind.legacyPromptKey) {
                seed.prompts[kind] = prompt
            }
            if let model = defaults.string(forKey: kind.legacyModelKey)
                ?? defaults.string(forKey: sharedLegacyModelKey)
            {
                seed.models[kind] = model
            }
        }
        return seed
    }
}
