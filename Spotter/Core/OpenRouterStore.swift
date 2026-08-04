import Combine
import Foundation

enum OpenRouterError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "OpenRouter is not enabled or has no API key."
        case .unauthorized: "OpenRouter rejected the API key."
        case .badResponse: "OpenRouter returned an unreadable response."
        case .http(let status): "OpenRouter request failed (HTTP \(status))."
        }
    }
}

/// API key, model choice, consent and the one chat-completion call for LLM-backed features.
/// Follows `CurrencyRateStore`'s network shape: ships off, consent lives here (never in
/// `AppSettings`), is re-checked on both sides of every `await`, and requests run on a private
/// cacheless session. The key and model are mirrored into `SettingsBackup` so they sync between
/// Macs, but the consent flag deliberately is not — an imported file must never grant network access.
@MainActor
final class OpenRouterStore: ObservableObject {
    static let provider = "OpenRouter"
    static let providerURL = URL(string: "https://openrouter.ai")!
    static let defaultModel = "openai/gpt-4o-mini"
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
    @Published private(set) var model: String
    /// Explicit user consent; absent reads as false, the only safe default for a network feature.
    @Published private(set) var isEnabled: Bool
    @Published private(set) var validation: Validation = .unknown

    private static let keyKey = "openrouter.api-key"
    private static let modelKey = "openrouter.model"
    private static let consentKey = "openrouter.enabled"
    private let defaults = UserDefaults.standard

    init() {
        apiKey = defaults.string(forKey: Self.keyKey) ?? ""
        model = defaults.string(forKey: Self.modelKey) ?? Self.defaultModel
        isEnabled = defaults.bool(forKey: Self.consentKey)
    }

    /// Consent granted and a key present — what LLM-backed features check before preferring this path.
    var isReady: Bool {
        isEnabled && !apiKey.isEmpty
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != apiKey else { return }
        apiKey = trimmed
        defaults.set(trimmed, forKey: Self.keyKey)
        validation = .unknown
    }

    func setModel(_ newModel: String) {
        let trimmed = newModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? Self.defaultModel : trimmed
        guard resolved != model else { return }
        model = resolved
        defaults.set(resolved, forKey: Self.modelKey)
    }

    /// The Settings toggle's only entry point, called after the user accepts the consent dialog.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
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

    /// One chat completion. Consent is re-checked on both sides of the request: it can be revoked from Settings while a reply is in flight, and a late response must not be surfaced.
    func chat(system: String, user: String) async throws -> String {
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
