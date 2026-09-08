import Foundation

/// The AI commands Spotter ships. They are ordinary `AICommand` records — what the case adds is a
/// fixed identity: the launcher entry id, the shortcut key and the prompt key they have always used,
/// which is how bindings and customizations survive the move to AI Commands.
enum AIBuiltInCommand: String, Codable, CaseIterable, Sendable {
    case define
    case grammar

    /// Fixed and never regenerated: every reference to a built-in — shortcut, favorite, learned
    /// ranking, backup — resolves through this id.
    var id: UUID {
        switch self {
        case .define: UUID(uuidString: "A1C0DE00-DEF1-4000-A000-000000000001")!
        case .grammar: UUID(uuidString: "A1C0DE00-64A1-4000-A000-000000000002")!
        }
    }

    var name: String {
        switch self {
        case .define: "Define Selected Text"
        case .grammar: "Check Selected Text Grammar"
        }
    }

    /// The chat session's title, which stays shorter than the command's own name.
    var sessionTitle: String {
        switch self {
        case .define: "Definition"
        case .grammar: "Grammar Check"
        }
    }

    var systemImage: String {
        switch self {
        case .define: "character.book.closed"
        case .grammar: "text.badge.checkmark"
        }
    }

    /// The launcher entry id from the Selection Tools era; favorites, visibility, aliases and learned
    /// ranking key off it, so it outlives every rename of the feature that owns it.
    var entryID: String { "command:selection-tools:" + rawValue }

    /// Where this command's binding has always been stored. Kept verbatim so an existing Define or
    /// Grammar shortcut needs no migration — the record is new, the key is not.
    var shortcutDefaultsKey: String { "KeyboardShortcuts_plugin.selection-tools." + rawValue }

    /// The pre-AI-Commands prompt key, read once to seed the record.
    var legacyPromptKey: String {
        switch self {
        case .define: "selection-tools.definition-prompt"
        case .grammar: "selection-tools.grammar-prompt"
        }
    }

    /// The pre-AI-Commands model key, read once to seed the record.
    var legacyModelKey: String {
        switch self {
        case .define: "openrouter.definition-model"
        case .grammar: "openrouter.grammar-model"
        }
    }

    /// The key these commands had in a backup's `hotkeys.pluginActions` map, still read on import and
    /// still written on export so an older build keeps both bindings.
    var legacyBackupKey: String { "ai-chat." + rawValue }
    /// The same map's key from before AI Chat took the two actions over from Selection Tools.
    var olderBackupKey: String { "selection-tools." + rawValue }

    var defaultPrompt: String {
        switch self {
        case .define: AIChatSelectionPrompts.defaultDefinition
        case .grammar: AIChatSelectionPrompts.defaultGrammar
        }
    }
}

/// One AI command: a prompt with the selected text substituted into it, its own shortcut and its own
/// model. Built-in and user-created commands are the same record and run through the same path.
struct AICommand: Codable, Hashable, Identifiable, Sendable {
    static let entryIDPrefix = "ai-command:"
    /// The one token a prompt substitutes, in the same single-brace shape a quicklink's `{argument}`
    /// uses. A prompt without it still works — the selection follows the instructions.
    static let placeholder = "{selection}"
    /// Fast, strong instruction-following and multilingual quality: the class the two shipped
    /// commands have always used for their first, quick answer.
    static let defaultBuiltInModel = "anthropic/claude-haiku-4.5"

    let id: UUID
    var name: String
    var prompt: String
    /// The model this command asks. `nil` means the chat model, so a command that pins nothing keeps
    /// following the default as the default changes.
    var model: String?
    /// Set for the two shipped commands, `nil` for user-created ones.
    let builtIn: AIBuiltInCommand?

    init(
        id: UUID = UUID(), name: String, prompt: String, model: String? = nil,
        builtIn: AIBuiltInCommand? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.model = model
        self.builtIn = builtIn
    }

    /// The shipped record for a built-in, before any customization.
    static func makeBuiltIn(_ kind: AIBuiltInCommand) -> AICommand {
        AICommand(
            id: kind.id, name: kind.name, prompt: kind.defaultPrompt,
            model: defaultBuiltInModel, builtIn: kind)
    }

    var isBuiltIn: Bool { builtIn != nil }
    var entryID: String { builtIn?.entryID ?? Self.entryIDPrefix + id.uuidString.lowercased() }
    var systemImage: String { builtIn?.systemImage ?? "sparkles" }
    /// A user command's session is titled by the command; a built-in keeps its shorter session name.
    var sessionTitle: String { builtIn?.sessionTitle ?? name }
    var shortcutDefaultsKey: String { Self.shortcutDefaultsKey(forID: id) }

    /// A built-in keeps its historical key; everything else gets its own namespace, keyed by UUID the
    /// way custom commands and quicklinks are.
    static func shortcutDefaultsKey(forID id: UUID) -> String {
        if let builtIn = AIBuiltInCommand.allCases.first(where: { $0.id == id }) {
            return builtIn.shortcutDefaultsKey
        }
        return "KeyboardShortcuts_aiCommandHotkey." + id.uuidString.lowercased()
    }

    static func id(fromEntryID entryID: String) -> UUID? {
        if let builtIn = AIBuiltInCommand.allCases.first(where: { $0.entryID == entryID }) {
            return builtIn.id
        }
        guard entryID.hasPrefix(entryIDPrefix) else { return nil }
        return UUID(uuidString: String(entryID.dropFirst(entryIDPrefix.count)))
    }

    /// The model actually asked: the pinned id, or the chat model when this command follows the
    /// default. A pinned id is never rewritten — a model the key can no longer reach stays the
    /// command's choice, and the request fails visibly rather than silently answering as some other
    /// model.
    func resolvedModel(chatModel: String) -> String {
        guard let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return chatModel }
        return trimmed
    }

    /// The first user turn this command sends.
    func rendered(selection: String) -> String {
        AICommandEngine.render(prompt: prompt, selection: selection)
    }

    var isDefault: Bool {
        guard let builtIn else { return false }
        let shipped = Self.makeBuiltIn(builtIn)
        return prompt == shipped.prompt && model == shipped.model
    }
}

enum AICommandValidationError: LocalizedError {
    case emptyName
    case emptyPrompt
    case duplicateName
    case invalidCharacter

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name for the command."
        case .emptyPrompt: "Enter a prompt to send."
        case .duplicateName: "An AI command with this name already exists."
        case .invalidCharacter: "Names and prompts cannot contain null characters."
        }
    }
}

/// Pre-AI-Commands prompts and models, read from their old keys once, to seed a built-in record the
/// stored list doesn't carry yet.
struct AICommandSeed: Equatable, Sendable {
    var prompts: [AIBuiltInCommand: String] = [:]
    var models: [AIBuiltInCommand: String] = [:]

    init(prompts: [AIBuiltInCommand: String] = [:], models: [AIBuiltInCommand: String] = [:]) {
        self.prompts = prompts
        self.models = models
    }
}

/// The pure half of AI Commands: substitution, validation and the repair that keeps a decoded list
/// usable. Foundation-only so `Tools/ai-chat-test.swift` compiles it standalone.
enum AICommandEngine {
    /// The prompt with the selection substituted in.
    ///
    /// Three cases, all deliberate: every occurrence of the token is replaced, a prompt with no token
    /// gets the selection appended after a blank line (which is exactly what the pre-AI-Commands
    /// prompts did, so a customized one keeps working), and the substitution is a single pass over
    /// the template — a selection that itself contains `{selection}` is inserted, never rescanned.
    static func render(prompt: String, selection: String) -> String {
        let parts = prompt.components(separatedBy: AICommand.placeholder)
        guard parts.count > 1 else {
            let instructions = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instructions.isEmpty else { return selection }
            guard !selection.isEmpty else { return instructions }
            return instructions + "\n\n" + selection
        }
        return parts.joined(separator: selection)
    }

    static func hasPlaceholder(_ prompt: String) -> Bool {
        prompt.contains(AICommand.placeholder)
    }

    /// Repairs whatever was decoded: both built-ins exist exactly once and lead in shipped order,
    /// records are trimmed, and unusable or duplicated ones drop out. A built-in the list doesn't
    /// carry is rebuilt from its defaults, seeded with any prompt or model the user set before AI
    /// Commands existed — which is the whole upgrade path for Define and Grammar.
    static func normalized(_ commands: [AICommand], seed: AICommandSeed = AICommandSeed())
        -> [AICommand]
    {
        var stored: [UUID: AICommand] = [:]
        var userOrder: [UUID] = []
        for command in commands {
            // A record claiming a built-in kind is that built-in, whatever id the file gave it.
            let id = command.builtIn?.id ?? command.id
            guard stored[id] == nil else { continue }
            guard let cleaned = cleaned(command, id: id) else { continue }
            stored[id] = cleaned
            if cleaned.builtIn == nil { userOrder.append(id) }
        }

        var result: [AICommand] = AIBuiltInCommand.allCases.map { kind in
            guard var command = stored[kind.id] else { return seeded(kind, seed: seed) }
            // The name is Spotter's, not the file's: it is what the docs and the launcher promise.
            command.name = kind.name
            return command
        }
        // Built-in names are reserved first, so an imported command can't shadow one.
        var names = Set(result.map { folded($0.name) })
        for id in userOrder {
            guard let command = stored[id], names.insert(folded(command.name)).inserted else {
                continue
            }
            result.append(command)
        }
        return result
    }

    private static func seeded(_ kind: AIBuiltInCommand, seed: AICommandSeed) -> AICommand {
        var command = AICommand.makeBuiltIn(kind)
        if let prompt = seed.prompts[kind]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !prompt.isEmpty
        {
            command.prompt = prompt
        }
        if let model = seed.models[kind]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !model.isEmpty
        {
            command.model = model
        }
        return command
    }

    /// Copy-and-clean rather than rebuild, so a field added later can never be dropped on import.
    private static func cleaned(_ command: AICommand, id: UUID) -> AICommand? {
        var value = AICommand(
            id: id, name: command.name.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: command.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            model: command.model?.trimmingCharacters(in: .whitespacesAndNewlines),
            builtIn: command.builtIn)
        if value.model?.isEmpty == true { value.model = nil }
        guard !value.name.isEmpty, !value.prompt.isEmpty, !value.name.contains("\0"),
            !value.prompt.contains("\0")
        else { return nil }
        return value
    }

    private static func folded(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: .current)
    }
}
