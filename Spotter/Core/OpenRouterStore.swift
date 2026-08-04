import Combine
import Foundation

enum OpenRouterError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "OpenRouter has no API key."
        case .unauthorized: "OpenRouter rejected the API key."
        case .badResponse: "OpenRouter returned an unreadable response."
        case .http(let status): "OpenRouter request failed (HTTP \(status))."
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
    @Published private(set) var validation: Validation = .unknown

    private static let keyKey = "openrouter.api-key"
    private static let legacyModelKey = "openrouter.model"
    private static let translationModelKey = "openrouter.translation-model"
    private static let grammarModelKey = "openrouter.grammar-model"
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

    /// One chat completion against the given model. The key is re-checked on both sides of the request: it can be cleared from Settings while a reply is in flight, and a late response must not be surfaced.
    func chat(system: String, user: String, model: String) async throws -> String {
        guard isReady else { throw OpenRouterError.notConfigured }
        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user),
            ])
        var request = URLRequest(url: Self.chatEndpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

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
            throw OpenRouterError.http(http.statusCode)
        }
        guard
            let reply = try? JSONDecoder().decode(ChatResponse.self, from: data),
            let content = reply.choices.first?.message.content, !content.isEmpty
        else { throw OpenRouterError.badResponse }
        return content
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
        let model: String
        let messages: [Message]
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
