import Combine
import Foundation

enum OpenRouterError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case badResponse
    /// A non-200 answer, carrying OpenRouter's own `error.message` when the body had one — "HTTP
    /// 402" alone hides the actual reason (usually insufficient credits).
    case http(Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "OpenRouter has no API key."
        case .unauthorized: return "OpenRouter rejected the API key."
        case .badResponse: return "OpenRouter returned an unreadable response."
        case .http(let status, let detail):
            if let detail, !detail.isEmpty {
                return "OpenRouter: \(detail) (HTTP \(status))"
            }
            return "OpenRouter request failed (HTTP \(status))."
        }
    }
}

/// API key, the chat model, effort and web-search choice, and the one chat-completion call for LLM-backed
/// features. Each AI command carries its own model choice (`Plugins/AIChat/AICommand.swift`) and falls back to this one.
/// The key is the gate (owner decision, Aug 2026): no key means no request can be made and the
/// AI features stay inert; entering — or syncing — a key is the consent act. Requests run
/// on a private cacheless session, re-checked for a key on both sides of every `await`. The key and
/// the chat model mirror into `SettingsBackup` so they sync between Macs.
@MainActor
final class OpenRouterStore: ObservableObject, AIToolModel {
    static let provider = "OpenRouter"
    static let providerURL = URL(string: "https://openrouter.ai")!
    private nonisolated static let chatEndpoint = URL(
        string: "https://openrouter.ai/api/v1/chat/completions")!
    private nonisolated static let keyEndpoint = URL(
        string: "https://openrouter.ai/api/v1/auth/key")!
    private nonisolated static let modelsEndpoint = URL(
        string: "https://openrouter.ai/api/v1/models")!

    enum Validation: Equatable {
        case unknown
        case checking
        case valid(String)
        case invalid(String)
    }

    enum CatalogState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var apiKey: String
    @Published private(set) var chatModel: String
    @Published private(set) var chatEffort: String?
    /// Every chat turn searches the web when on; off by default because each search costs extra.
    @Published private(set) var webSearch: Bool
    @Published private(set) var validation: Validation = .unknown
    /// The published model list behind the Settings brand → model menus. Session-only: never
    /// persisted, so a stale catalog can't outlive the app.
    @Published private(set) var catalog: [OpenRouterModelBrand] = []
    @Published private(set) var catalogState: CatalogState = .idle

    private static let keyKey = "openrouter.api-key"
    private static let chatModelKey = "openrouter.chat-model"
    private static let chatEffortKey = "openrouter.chat-effort"
    private static let webSearchKey = "openrouter.web-search"
    private let defaults: UserDefaults
    private let requestSession: URLSession
    private var catalogTask: Task<Void, Never>?
    private var catalogFetchedAt: Date?

    /// The Jev-era mappings found at launch, which `AppCore` hands to `AICommandStore` so category pins resolve.
    let legacyRouting: AILegacyRouting?

    init(defaults: UserDefaults = .standard, session: URLSession? = nil) {
        self.defaults = defaults
        requestSession = session ?? Self.session
        apiKey = defaults.string(forKey: Self.keyKey) ?? ""
        webSearch = defaults.bool(forKey: Self.webSearchKey)
        let savedModel = defaults.string(forKey: Self.chatModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSavedModel = savedModel?.isEmpty == false
        chatModel = Self.resolve(savedModel ?? "", default: AIModelChoice.defaultChat.model)
        // A saved model without a saved effort predates efforts, so it keeps the model's own default.
        chatEffort = defaults.string(forKey: Self.chatEffortKey).map(AIReasoningEffort.normalized)
            ?? (hasSavedModel ? nil : AIModelChoice.defaultChat.effort)
        if let data = defaults.data(forKey: AILegacyRouting.defaultsKey) {
            let routing = try? JSONDecoder().decode(AILegacyRouting.self, from: data)
            legacyRouting = routing
            // The Everyday tier answered every unclassified turn, so it was the chat model in practice.
            if let everyday = routing?.choice(for: "everyday") {
                chatModel = everyday.model
                chatEffort = everyday.effort
            } else if routing != nil {
                chatEffort = nil
            }
            defaults.set(chatModel, forKey: Self.chatModelKey)
            defaults.set(chatEffort ?? "", forKey: Self.chatEffortKey)
            defaults.removeObject(forKey: AILegacyRouting.defaultsKey)
        } else {
            legacyRouting = hasSavedModel ? nil : .shipped
        }
    }

    /// A key is present, so LLM-backed features are allowed to make a request.
    var isReady: Bool {
        !apiKey.isEmpty
    }

    var onCredentialsChanged: (() -> Void)?

    var chatChoice: AIModelChoice { AIModelChoice(model: chatModel, effort: chatEffort) }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != apiKey else { return }
        apiKey = trimmed
        onCredentialsChanged?()
        defaults.set(trimmed, forKey: Self.keyKey)
        validation = .unknown
        // The key is the gate, so losing it also ends the catalog's reason to exist.
        if trimmed.isEmpty {
            catalogTask?.cancel()
            catalogTask = nil
            catalogFetchedAt = nil
            catalog = []
            catalogState = .idle
        }
    }


    func setChatChoice(_ choice: AIModelChoice) {
        let model = Self.resolve(choice.model, default: AIModelChoice.defaultChat.model)
        let effort = AIReasoningEffort.normalized(choice.effort)
        guard model != chatModel || effort != chatEffort else { return }
        chatModel = model
        chatEffort = effort
        defaults.set(model, forKey: Self.chatModelKey)
        // Stored as "" for Model Default, so it stays distinguishable from a pre-effort install.
        defaults.set(effort ?? "", forKey: Self.chatEffortKey)
    }

    func setWebSearch(_ enabled: Bool) {
        guard enabled != webSearch else { return }
        webSearch = enabled
        defaults.set(enabled, forKey: Self.webSearchKey)
    }

    private nonisolated static func resolve(_ model: String, default fallback: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Manual key check from Settings; hits the key-metadata endpoint, never a model.
    func validate() async {
        let key = apiKey
        guard !key.isEmpty else {
            validation = .invalid("Enter an API key first.")
            return
        }
        validation = .checking
        do {
            var request = URLRequest(url: Self.keyEndpoint, timeoutInterval: 20)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await requestSession.data(for: request)
            // The key may have changed while the request was in flight; a stale result must not label the new key.
            guard apiKey == key else { return }
            guard let http = response as? HTTPURLResponse else {
                validation = .invalid("Unreadable response from \(Self.provider).")
                return
            }
            switch http.statusCode {
            case 200:
                let info = try? JSONDecoder().decode(KeyInfo.self, from: data)
                if let label = info?.data.label, !label.isEmpty {
                    validation = .valid("Key valid · \(label)")
                } else {
                    validation = .valid("Key valid")
                }
            case 401, 403:
                validation = .invalid("\(Self.provider) rejected this key.")
            default:
                validation = .invalid("\(Self.provider) answered HTTP \(http.statusCode).")
            }
        } catch {
            guard apiKey == key else { return }
            validation = .invalid("Couldn't reach \(Self.provider) — check your connection.")
        }
    }

    /// Loads the brand → model menu, refreshing whenever Settings opens the AI Chat pane so the list
    /// is what OpenRouter publishes right now. Reads the public catalog only — no key is sent, and
    /// nothing about this Mac or its conversations leaves with the request. Still gated on a key
    /// present: without one the models can't be used, so there is no reason to reach out.
    func refreshCatalog(force: Bool = false) {
        guard isReady else { return }
        if !force, let fetched = catalogFetchedAt, !catalog.isEmpty,
            Date().timeIntervalSince(fetched) < Self.catalogFreshness
        { return }
        guard catalogTask == nil else { return }
        catalogState = .loading
        catalogTask = Task { [weak self] in
            await self?.loadCatalog()
            self?.catalogTask = nil
        }
    }

    func reasoningEfforts(for model: String) -> [String] {
        catalog.lazy.flatMap(\.models).first(where: { $0.id == model })?.reasoningEfforts ?? []
    }

    private func resolvedEffort(_ effort: String?, model: String) async throws -> String? {
        guard let effort = AIReasoningEffort.normalized(effort) else { return nil }
        let key = apiKey
        refreshCatalog()
        await catalogTask?.value
        try Task.checkCancellation()
        guard acceptsReply(for: key) else { throw OpenRouterError.notConfigured }
        return AIReasoningEffort.resolve(effort, supported: reasoningEfforts(for: model))
    }

    private func loadCatalog() async {
        do {
            var request = URLRequest(url: Self.modelsEndpoint, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await requestSession.data(for: request)
            try Task.checkCancellation()
            // The key can be cleared while the list is in flight; a late catalog must not arrive
            // for a store that no longer has a reason to hold one.
            guard isReady else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                catalogState = .failed("\(Self.provider) couldn't list its models.")
                return
            }
            let brands = try OpenRouterModelCatalog.brands(fromJSON: data)
            guard !brands.isEmpty else {
                catalogState = .failed("\(Self.provider) returned no models.")
                return
            }
            catalog = brands
            catalogFetchedAt = Date()
            catalogState = .ready
        } catch is CancellationError {
            catalogState = .idle
        } catch {
            guard isReady else { return }
            AppLog.error("openrouter", "model catalog failed: \(error.localizedDescription)")
            catalogState = .failed("Couldn't reach \(Self.provider) — check your connection.")
        }
    }

    /// Long enough that reopening Settings doesn't re-fetch, short enough that a day-old app still
    /// sees today's models.
    private nonisolated static let catalogFreshness: TimeInterval = 15 * 60

    // Re-check the exact key before every delivery so a replaced credential cannot receive late output.
    func chat(
        messages: [(role: String, content: String)], model: String, webSearch: Bool = false, effort: String? = nil,
        onDelta: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        try await chat(messages: messages, model: model, webSearch: webSearch, imageDataURLs: [:], effort: effort, onDelta: onDelta)
    }

    func chat(messages: [(role: String, content: String)], model: String, webSearch: Bool,
        imageDataURLs: [Int: [String]], effort: String? = nil, completionLimit: Int = 4096, requiresCompleteReply: Bool = false,
        onDelta: @escaping @MainActor @Sendable (String) -> Void) async throws {
        guard isReady else { throw OpenRouterError.notConfigured }
        let requestKey = apiKey
        let effort = try await resolvedEffort(effort, model: model)
        guard acceptsReply(for: requestKey) else { throw OpenRouterError.notConfigured }
        let body = ChatRequest(
            model: model,
            messages: messages.enumerated().map { index, message in
                let images = imageDataURLs[index] ?? []
                let content: AIJSON = images.isEmpty ? .string(message.content) : .array(
                    [.object(["type": .string("text"), "text": .string(message.content)])]
                    + images.map { .object(["type": .string("image_url"), "image_url": .object(["url": .string($0)])]) })
                return .init(role: message.role, content: content)
            },
            max_tokens: min(max(completionLimit, 1), 16_384),
            plugins: webSearch ? [.init(id: "web", max_results: 5)] : nil,
            reasoning: effort.map { ["effort": $0] })
        var request = URLRequest(url: Self.chatEndpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(requestKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        try await Self.consumeStream(request, session: requestSession, requiresCompleteReply: requiresCompleteReply) { [weak self] delta in
            try Task.checkCancellation()
            guard let self else { throw OpenRouterError.notConfigured }
            try await self.deliver(delta, for: requestKey, to: onDelta)
        }
        try Task.checkCancellation()
        guard acceptsReply(for: requestKey) else { throw OpenRouterError.notConfigured }
    }

    func toolTurn(messages: [AIJSON], tools: [AIToolDefinition], model: String, webSearch: Bool, effort: String? = nil) async throws -> AIToolTurn {
        guard isReady else { throw OpenRouterError.notConfigured }
        let key = apiKey
        let effort = try await resolvedEffort(effort, model: model)
        guard acceptsReply(for: key) else { throw OpenRouterError.notConfigured }
        let result = try await Self.fetchToolTurn(messages: messages, tools: tools.map(\.wire),
            model: model, webSearch: webSearch, effort: effort, key: key, session: requestSession)
        try Task.checkCancellation()
        guard acceptsReply(for: key) else { throw OpenRouterError.notConfigured }
        return result
    }

    private nonisolated static func fetchToolTurn(messages: [AIJSON], tools: [AIJSON], model: String,
        webSearch: Bool, effort: String?, key: String, session: URLSession) async throws -> AIToolTurn {
        var body: [String: AIJSON] = ["model": .string(model), "messages": .array(messages),
            "max_tokens": .number(Double(maxCompletionTokens)), "stream": .bool(false),
            "provider": .object(["require_parameters": .bool(true)])]
        if let effort { body["reasoning"] = .object(["effort": .string(effort)]) }
        if !tools.isEmpty { body["tools"] = .array(tools); body["tool_choice"] = .string("auto") }
        if webSearch { body["plugins"] = .array([.object(["id": .string("web"), "max_results": .number(5)])]) }
        var request = URLRequest(url: chatEndpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try AIJSON.object(body).data()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            guard data.count <= 2_097_152 else { throw OpenRouterStream.Failure.oversized }
        }
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw OpenRouterError.unauthorized }
        guard http.statusCode == 200 else { throw OpenRouterError.http(http.statusCode, detail: errorDetail(in: data)) }
        struct Response: Decodable {
            struct Choice: Decodable { let message: AIToolTurn; let finish_reason: String? }
            let choices: [Choice]
        }
        guard let choice = try JSONDecoder().decode(Response.self, from: data).choices.first,
            choice.finish_reason != "error", choice.finish_reason != "length",
            choice.message.content?.isEmpty == false || choice.message.tool_calls?.isEmpty == false else {
            throw OpenRouterError.badResponse
        }
        return choice.message
    }

    private func deliver(_ delta: String, for key: String, to callback: @MainActor (String) -> Void) throws {
        try Task.checkCancellation()
        guard acceptsReply(for: key) else { throw OpenRouterError.notConfigured }
        callback(delta)
    }

    private func acceptsReply(for key: String) -> Bool { isReady && apiKey == key }

    private nonisolated static func consumeStream(
        _ request: URLRequest, session: URLSession, requiresCompleteReply: Bool = false,
        onDelta: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
        if http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                if data.count >= 65_536 { break }
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw OpenRouterError.unauthorized }
            throw OpenRouterError.http(http.statusCode, detail: errorDetail(in: data))
        }
        var parser = OpenRouterStream(requiresCompleteReply: requiresCompleteReply)
        var count = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            if let delta = try parser.feed(byte), !delta.isEmpty {
                count += delta.utf8.count
                guard count <= 2_097_152 else { throw OpenRouterStream.Failure.oversized }
                try await onDelta(delta)
            }
            if parser.done { break }
        }
        try parser.finish()
        guard count > 0 else { throw OpenRouterError.badResponse }
    }

    /// Plenty for palette answers, tiny next to any model's window — the cap exists for the credit
    /// reservation above, not to truncate.
    private nonisolated static let maxCompletionTokens = 4_096

    /// OpenRouter error bodies carry `{"error": {"message": …}}`; surface it instead of a bare code.
    private nonisolated static func errorDetail(in data: Data) -> String? {
        struct ErrorBody: Decodable {
            struct Inner: Decodable {
                let message: String?
            }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message
    }

    /// Deliberately not `URLSession.shared`: cacheless, so no response copy outlives the exchange (same rule as `CurrencyRateStore`).
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: AIJSON
        }
        struct Plugin: Encodable {
            let id: String
            let max_results: Int
        }
        let model: String
        let messages: [Message]
        let max_tokens: Int
        let stream = true
        // Synthesized Codable omits a nil optional, so non-search requests stay byte-identical.
        let plugins: [Plugin]?
        let reasoning: [String: String]?
    }

    private struct KeyInfo: Decodable {
        struct Data: Decodable {
            let label: String?
        }
        let data: Data
    }
}
