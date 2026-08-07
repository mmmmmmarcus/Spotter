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

/// API key, per-action model choices and the one chat-completion call for LLM-backed features.
/// The key is the gate (owner decision, Aug 2026): no key means no request can be made and the
/// on-device services serve instead; entering — or syncing — a key is the consent act. Requests run
/// on a private cacheless session, re-checked for a key on both sides of every `await`. The key and
/// models mirror into `SettingsBackup` so they sync between Macs.
@MainActor
final class OpenRouterStore: ObservableObject {
    static let provider = "OpenRouter"
    static let providerURL = URL(string: "https://openrouter.ai")!
    /// Fast, strong instruction-following and multilingual quality — the right class for short interactive selections.
    static let defaultTranslationModel = "anthropic/claude-haiku-4.5"
    static let defaultGrammarModel = "anthropic/claude-haiku-4.5"
    /// Chat carries multi-turn reasoning, so it defaults a class up from the quick selection actions.
    static let defaultChatModel = "anthropic/claude-sonnet-5"
    private nonisolated static let chatEndpoint = URL(
        string: "https://openrouter.ai/api/v1/chat/completions")!
    private nonisolated static let keyEndpoint = URL(
        string: "https://openrouter.ai/api/v1/auth/key")!

    enum Validation: Equatable {
        case unknown
        case checking
        case valid(String)
        case invalid(String)
    }

    @Published private(set) var apiKey: String
    @Published private(set) var translationModel: String
    @Published private(set) var grammarModel: String
    @Published private(set) var chatModel: String
    /// Lets chat requests search the web through OpenRouter's Exa-backed plugin. Off by default —
    /// each search adds a small per-request cost on the same key.
    @Published private(set) var chatWebSearch: Bool
    @Published private(set) var validation: Validation = .unknown

    private static let keyKey = "openrouter.api-key"
    private static let legacyModelKey = "openrouter.model"
    private static let translationModelKey = "openrouter.translation-model"
    private static let grammarModelKey = "openrouter.grammar-model"
    private static let chatModelKey = "openrouter.chat-model"
    private static let chatWebSearchKey = "openrouter.chat-web-search"
    private let defaults = UserDefaults.standard

    init() {
        apiKey = defaults.string(forKey: Self.keyKey) ?? ""
        // One release carried a single shared model key; seed both per-action models from it once.
        let legacy = defaults.string(forKey: Self.legacyModelKey)
        translationModel =
            defaults.string(forKey: Self.translationModelKey) ?? legacy
            ?? Self.defaultTranslationModel
        grammarModel =
            defaults.string(forKey: Self.grammarModelKey) ?? legacy ?? Self.defaultGrammarModel
        chatModel = defaults.string(forKey: Self.chatModelKey) ?? Self.defaultChatModel
        chatWebSearch = defaults.bool(forKey: Self.chatWebSearchKey)
    }

    /// A key is present — LLM-backed features prefer this path; without one they fall back on-device.
    var isReady: Bool {
        !apiKey.isEmpty
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != apiKey else { return }
        apiKey = trimmed
        defaults.set(trimmed, forKey: Self.keyKey)
        validation = .unknown
    }

    func setTranslationModel(_ newModel: String) {
        let resolved = Self.resolve(newModel, default: Self.defaultTranslationModel)
        guard resolved != translationModel else { return }
        translationModel = resolved
        defaults.set(resolved, forKey: Self.translationModelKey)
    }

    func setGrammarModel(_ newModel: String) {
        let resolved = Self.resolve(newModel, default: Self.defaultGrammarModel)
        guard resolved != grammarModel else { return }
        grammarModel = resolved
        defaults.set(resolved, forKey: Self.grammarModelKey)
    }

    func setChatWebSearch(_ enabled: Bool) {
        guard enabled != chatWebSearch else { return }
        chatWebSearch = enabled
        defaults.set(enabled, forKey: Self.chatWebSearchKey)
    }

    func setChatModel(_ newModel: String) {
        let resolved = Self.resolve(newModel, default: Self.defaultChatModel)
        guard resolved != chatModel else { return }
        chatModel = resolved
        defaults.set(resolved, forKey: Self.chatModelKey)
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
            let (data, response) = try await Self.session.data(for: request)
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

    /// The single-turn convenience the selection actions use.
    func chat(system: String, user: String, model: String) async throws -> String {
        try await chat(
            messages: [(role: "system", content: system), (role: "user", content: user)],
            model: model)
    }

    /// One chat completion against the given model, any number of turns. The key is re-checked on both sides of the request: it can be cleared from Settings while a reply is in flight, and a late response must not be surfaced.
    func chat(
        messages: [(role: String, content: String)], model: String, webSearch: Bool = false
    ) async throws -> String {
        guard isReady else { throw OpenRouterError.notConfigured }
        // Capped: OpenRouter reserves credits for the whole completion window up front, so an
        // uncapped request 402s on a small balance even when the actual reply would cost cents.
        let body = ChatRequest(
            model: model,
            messages: messages.map { .init(role: $0.role, content: $0.content) },
            max_tokens: Self.maxCompletionTokens,
            plugins: webSearch ? [.init(id: "web", max_results: 5)] : nil)
        var request = URLRequest(url: Self.chatEndpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await Self.session.data(for: request)
            try Task.checkCancellation()
            guard isReady else { throw OpenRouterError.notConfigured }
            guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
            switch http.statusCode {
            case 200:
                break
            case 401, 403:
                throw OpenRouterError.unauthorized
            default:
                throw OpenRouterError.http(
                    http.statusCode, detail: Self.errorDetail(in: data))
            }
            guard
                let reply = try? JSONDecoder().decode(ChatResponse.self, from: data),
                let content = reply.choices.first?.message.content, !content.isEmpty
            else { throw OpenRouterError.badResponse }
            return content
        } catch let error as CancellationError {
            throw error
        } catch {
            AppLog.error(
                "openrouter",
                "chat(model: \(model), turns: \(messages.count)) failed: "
                    + ((error as? OpenRouterError)?.errorDescription ?? error.localizedDescription))
            throw error
        }
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
            let content: String
        }
        struct Plugin: Encodable {
            let id: String
            let max_results: Int
        }
        let model: String
        let messages: [Message]
        let max_tokens: Int
        // Synthesized Codable omits a nil optional, so non-search requests stay byte-identical.
        let plugins: [Plugin]?
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct KeyInfo: Decodable {
        struct Data: Decodable {
            let label: String?
        }
        let data: Data
    }
}
