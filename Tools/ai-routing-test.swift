import Foundation
import Synchronization

enum AppLog {
    static func error(_ category: String, _ message: String) {}
}

private final class DecisionProtocol: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable {
        var status = 200
        var data = Data()
        var delay = 0.0
        var error: URLError?
        var requests: [URLRequest] = []
    }
    static let fixture = Mutex(Fixture())
    private let stopped = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.fixture.withLock { fixture in
            fixture.requests.append(request)
            return fixture
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [self] in
            guard !stopped.withLock({ $0 }) else { return }
            if let error = response.error { client?.urlProtocol(self, didFailWithError: error); return }
            let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopped.withLock { $0 = true } }
}

@main
@MainActor
private struct RoutingTests {
    static var count = 0
    static let preferences = AIRoutingPreferences(everydayModel: "vendor/fast",
        professionalModel: "vendor/work", reasoningModel: "vendor/deep")
    static let prompt = [(role: "user", content: "Explain this code")]

    static func check(_ value: Bool, _ name: String) {
        guard value else { fatalError("FAIL: \(name)") }
        count += 1
    }

    static func rejects(_ name: String, _ action: () throws -> Void) {
        do { try action(); fatalError("FAIL: \(name)") } catch { count += 1 }
    }

    static func answer(_ category: AIRoutingCategory, probabilities: [String: Double]? = nil) -> Data {
        let values = probabilities ?? Dictionary(uniqueKeysWithValues: AIRoutingCategory.allCases.map {
            ($0.rawValue, $0 == category ? 0.9 : 0.05)
        })
        return try! JSONSerialization.data(withJSONObject: ["answers": ["route": [
            "type": "choice", "choice": category.rawValue, "confidence": 0.8, "probabilities": values
        ]]])
    }

    static func main() async throws {
        try pureDecisions()
        try await transportAndConsent()
        print("AI Routing: \(count) checks passed")
    }

    static func pureDecisions() throws {
        for category in AIRoutingCategory.allCases {
            let result = try AIRoutingDecision.selection(from: answer(category), preferences: preferences, defaultModel: "default")
            check(result.model == preferences.model(for: category) && result.category == category && result.fallback == nil,
                "each category maps only to the user's configured model")
        }
        let uncertain = try AIRoutingDecision.selection(from: answer(.professional,
            probabilities: ["everyday": 0.3, "professional": 0.4, "reasoning": 0.3]), preferences: preferences, defaultModel: "default")
        check(uncertain.model == "default" && uncertain.fallback == .uncertain, "an ambiguous distribution uses the declared default")
        let empty = try AIRoutingDecision.selection(from: answer(.reasoning), preferences: AIRoutingPreferences(), defaultModel: "default")
        check(empty.model == "default" && empty.category == .reasoning, "an unset tier resolves to Chat Model")
        for invalid in [Data("{}".utf8), Data("not JSON".utf8), answer(.professional,
            probabilities: ["everyday": 0, "professional": 1.1, "reasoning": -0.1]),
            answer(.professional, probabilities: ["everyday": 0.1, "professional": 0.1, "reasoning": 0.8]),
            answer(.everyday, probabilities: ["everyday": 0.9, "professional": 0.05, "reasoning": 0.05, "injected-model": 0])] {
            rejects("malformed or inconsistent choices cannot select a model") {
                _ = try AIRoutingDecision.selection(from: invalid, preferences: preferences, defaultModel: "default")
            }
        }
        let messages: [AIRoutingDecision.Message] = [
            .init(role: "system", content: "Internal instructions"),
            .init(role: "user", content: "先前的问题"), .init(role: "assistant", content: "Earlier answer"),
            .init(role: "user", content: "继续解释 🧭")
        ]
        let request = try AIRoutingDecision.request(messages: messages)
        check(request.state.latest_request == "继续解释 🧭" && request.state.recent_conversation.map(\.role) == ["user", "assistant"],
            "the decision has the latest prompt and recent conversational context without system instructions")
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        check(wire["model"] as? String == "typesafe/jev-1.13", "the classifier uses the pinned Decisions model, not Jev Router")
        let questions = wire["questions"] as! [String: [String: Any]]
        check(Set((questions["route"]?["criteria"] as! [String: String]).keys) == Set(AIRoutingCategory.allCases.map(\.rawValue)),
            "Jev can choose only a tier, never invent a target model")
        let bounded = try AIRoutingDecision.request(messages: (0..<20).map {
            .init(role: $0 == 19 ? "user" : "assistant", content: String($0))
        })
        check(bounded.state.recent_conversation.count == 6 && bounded.state.recent_conversation.first?.content == "13",
            "only six recent context messages accompany the full latest prompt")
        rejects("oversize prompts are not silently truncated for classification") {
            _ = try AIRoutingDecision.request(messages: [.init(role: "user", content: String(repeating: "x", count: 16_001))])
        }
        rejects("multibyte input shares the same bounded request budget") {
            _ = try AIRoutingDecision.request(messages: [.init(role: "user", content: String(repeating: "🧭", count: 4_001))])
        }
        let message = AIChatMessage(role: .assistant, text: "A reply", routing: uncertain)
        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: JSONEncoder().encode(message))
        check(decoded == message, "routing metadata survives conversation backup")
        let oldJSON = "{\"id\":\"\(UUID())\",\"role\":\"assistant\",\"text\":\"Old reply\"}"
        check(try JSONDecoder().decode(AIChatMessage.self, from: Data(oldJSON.utf8)).routing == nil,
            "old messages without routing metadata remain readable")
        let unknown = oldJSON.dropLast() + ",\"routing\":{\"model\":\"future\",\"category\":\"unknown\"}}"
        check(try JSONDecoder().decode(AIChatMessage.self, from: Data(unknown.utf8)).text == "Old reply",
            "unrecognized future metadata cannot erase a conversation")
    }

    static func reset(data: Data = answer(.professional), status: Int = 200, delay: Double = 0, error: URLError? = nil) {
        DecisionProtocol.fixture.withLock { $0 = .init(status: status, data: data, delay: delay, error: error) }
    }

    static func requestCount() -> Int { DecisionProtocol.fixture.withLock { $0.requests.count } }

    static func awaitRequest() async {
        for _ in 0..<1000 {
            if requestCount() > 0 { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Decision fixture did not receive a request")
    }

    static func transportAndConsent() async throws {
        let suite = "spotter-routing-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DecisionProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = JevDecisionClient(session: session)
        defaults.set("vendor/previous", forKey: "openrouter.chat-model")
        let store = OpenRouterStore(defaults: defaults, decisionClient: client)
        check(AIRoutingCategory.allCases.allSatisfy { store.aiRouting.model(for: $0) == "vendor/previous" },
            "empty mappings inherit the former chat model rather than losing the saved choice")
        reset()
        check(AIRoutingCategory.allCases.allSatisfy { !store.aiRouting.model(for: $0).isEmpty },
            "fresh installations have explicit model choices for every category")
        store.setAPIKey("fixture-key")
        check(try await store.selectChatModel(messages: prompt, defaultModel: "default") != nil && requestCount() == 1,
            "adding a key enables Jev without a separate consent switch")
        reset()
        store.setAIRouting(preferences)
        let chosen = try await store.selectChatModel(messages: prompt, defaultModel: "default")
        check(chosen?.model == "vendor/work", "the real transport and store map the typed decision")
        let request = DecisionProtocol.fixture.withLock { $0.requests.first! }
        check(request.url == JevDecisionClient.endpoint && request.httpMethod == "POST"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key", "the request uses the Decisions endpoint and OpenRouter key")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as! [String: Any]
        legacy["isEnabled"] = false
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "openrouter.ai-routing")
        let restored = OpenRouterStore(defaults: defaults, decisionClient: client)
        check(try await restored.selectChatModel(messages: prompt, defaultModel: "default") != nil,
            "a legacy disabled flag cannot disable automatic selection")
        check(restored.aiRouting == preferences, "routing choices survive a store restart")

        for fixture in [(Data("malformed".utf8), 200), (answer(.professional), 503), (Data(repeating: 32, count: 65_537), 200)] {
            reset(data: fixture.0, status: fixture.1)
            let fallback = try await store.selectChatModel(messages: prompt, defaultModel: "default")
            check(fallback?.model == "vendor/fast" && fallback?.fallback == .unavailable, "unavailable or malformed classification uses a labelled default")
        }
        reset(error: URLError(.timedOut))
        check(try await store.selectChatModel(messages: prompt, defaultModel: "default")?.fallback == .unavailable,
            "a timeout does not block ordinary chat")
        reset()
        let long = try await store.selectChatModel(messages: [("user", String(repeating: "x", count: 16_001))], defaultModel: "default")
        check(long?.fallback == .inputTooLong && requestCount() == 0, "oversize prompts bypass the decision call")
        reset(status: 401)
        do {
            _ = try await store.selectChatModel(messages: prompt, defaultModel: "default")
            fatalError("Unauthorized routing must not fall back")
        } catch OpenRouterError.unauthorized { count += 1 }

        reset(delay: 0.1)
        let cancelled = Task { try await store.selectChatModel(messages: prompt, defaultModel: "default") }
        await awaitRequest()
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancellation must not become a fallback") }
        catch is CancellationError { count += 1 }

        reset(delay: 0.1)
        let revoked = Task { try await store.selectChatModel(messages: prompt, defaultModel: "default") }
        await awaitRequest()
        store.setAIRouting(AIRoutingPreferences())
        store.setAIRouting(preferences)
        do { _ = try await revoked.value; fatalError("A decision invalidated by changed mappings must stay cancelled") }
        catch is CancellationError { count += 1 }

        reset(delay: 0.1)
        let changedKey = Task { try await store.selectChatModel(messages: prompt, defaultModel: "default") }
        await awaitRequest()
        store.setAPIKey("")
        do { _ = try await changedKey.value; fatalError("Clearing the key must reject an in-flight decision") }
        catch OpenRouterError.notConfigured { count += 1 }
        reset()
        do { _ = try await store.selectChatModel(messages: prompt, defaultModel: "default"); fatalError("A missing key must reject before dispatch") }
        catch OpenRouterError.notConfigured { check(requestCount() == 0, "no key means no request") }
    }
}
