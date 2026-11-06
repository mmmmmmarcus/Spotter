import Foundation
import Synchronization

enum AppLog {
    static func error(_ category: String, _ message: String) {}
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
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
private struct OpenRouterStoreTests {
    static var count = 0

    static func check(_ value: Bool, _ name: String) {
        guard value else { fatalError("FAIL: \(name)") }
        count += 1
    }

    static func main() async throws {
        try chatModelMigration()
        try await effortTransport()
        try await webSearchTransport()
        print("OpenRouter store: \(count) checks passed")
    }

    static func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "spotter-openrouter-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    static func chatModelMigration() throws {
        withDefaults { defaults in
            let fresh = OpenRouterStore(defaults: defaults)
            check(fresh.chatChoice == AIModelChoice.defaultChat && fresh.chatChoice.effort == "low",
                "fresh installations default to Codex Luna with Low effort")
            check(!fresh.webSearch && !fresh.isReady, "web search ships off and new defaults grant no network access")
            check(fresh.legacyRouting == .shipped, "an install that never saved mappings migrates presets to the shipped tiers")
            fresh.setChatChoice(AIModelChoice(model: "vendor/chosen", effort: nil))
            fresh.setWebSearch(true)
            let restored = OpenRouterStore(defaults: defaults)
            check(restored.chatChoice == AIModelChoice(model: "vendor/chosen") && restored.webSearch,
                "a Model Default effort and the search setting survive a restart")
            check(restored.legacyRouting == nil, "a migrated install hands no mappings to the command store")
        }
        withDefaults { defaults in
            defaults.set("vendor/previous", forKey: "openrouter.chat-model")
            let store = OpenRouterStore(defaults: defaults)
            check(store.chatChoice == AIModelChoice(model: "vendor/previous"),
                "a saved model from before efforts keeps the model's own default effort")
        }
        try withDefaults { defaults in
            let routing = AILegacyRouting(everydayModel: "vendor/fast", professionalModel: "vendor/work",
                reasoningModel: "vendor/deep", everydayEffort: "low", professionalEffort: "medium", reasoningEffort: "high")
            var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(routing)) as! [String: Any]
            legacy["isEnabled"] = false
            defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: AILegacyRouting.defaultsKey)
            defaults.set("vendor/previous", forKey: "openrouter.chat-model")
            let store = OpenRouterStore(defaults: defaults)
            check(store.chatChoice == AIModelChoice(model: "vendor/fast", effort: "low"),
                "the Everyday mapping becomes the chat model and effort")
            check(store.legacyRouting == routing, "the saved mappings are handed over for command presets")
            check(defaults.data(forKey: AILegacyRouting.defaultsKey) == nil, "the mappings are retired once migrated")
            check(OpenRouterStore(defaults: defaults).chatChoice == store.chatChoice, "the migrated pair is persisted")
        }
        withDefaults { defaults in
            defaults.set(Data(#"{"everydayModel":"","professionalModel":"vendor/work"}"#.utf8), forKey: AILegacyRouting.defaultsKey)
            defaults.set("vendor/previous", forKey: "openrouter.chat-model")
            let store = OpenRouterStore(defaults: defaults)
            check(store.chatChoice == AIModelChoice(model: "vendor/previous"),
                "an unset Everyday tier keeps the previous chat model, as Jev's fallback did")
        }
    }

    static func reset(data: Data = Data(), status: Int = 200, delay: Double = 0, error: URLError? = nil) {
        FixtureProtocol.fixture.withLock { $0 = .init(status: status, data: data, delay: delay, error: error) }
    }

    static func requestCount() -> Int { FixtureProtocol.fixture.withLock { $0.requests.count } }

    static func awaitRequest() async {
        for _ in 0..<1000 {
            if requestCount() > 0 { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        fatalError("Fixture did not receive a request")
    }

    static func capturedBody() throws -> [String: Any] {
        let request = FixtureProtocol.fixture.withLock { $0.requests.last! }
        var data = request.httpBody ?? Data()
        if data.isEmpty, let input = request.httpBodyStream {
            input.open()
            defer { input.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while input.hasBytesAvailable {
                let count = input.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func effortTransport() async throws {
        let suite = "spotter-effort-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = OpenRouterStore(defaults: defaults, session: session)
        store.setAPIKey("fixture-key")
        let catalog = Data(#"{"data":[{"id":"vendor/reasoning","reasoning":{"supported_efforts":["low","high"]}},{"id":"vendor/plain"}]}"#.utf8)
        reset(data: catalog)
        store.refreshCatalog()
        for _ in 0..<1000 {
            if store.catalogState == .ready { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        check(store.reasoningEfforts(for: "vendor/reasoning") == ["low", "high"], "live catalog controls effort choices")
        let stream = Data("data: {\"choices\":[{\"delta\":{\"content\":\"Answer\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8)
        for (model, effort, expected) in [("vendor/reasoning", "high", "high" as String?), ("vendor/reasoning", "invalid", nil), ("vendor/plain", "high", nil)] {
            reset(data: stream)
            var reply = ""
            try await store.chat(messages: [("user", "fixture")], model: model, effort: effort) { reply += $0 }
            let body = try capturedBody()
            check((body["reasoning"] as? [String: String])?["effort"] == expected && reply == "Answer", "streaming request sends only an offered effort")
            check(requestCount() == 1, "cached effort discovery adds no extra request")
        }
        reset(data: stream)
        try await store.chat(messages: [], model: "vendor/reasoning") { _ in }
        check(try capturedBody()["reasoning"] == nil, "model default omits the reasoning parameter")
        reset(data: Data(#"{"choices":[{"message":{"content":"Done"},"finish_reason":"stop"}]}"#.utf8))
        _ = try await store.toolTurn(messages: [], tools: [], model: "vendor/reasoning", webSearch: false, effort: "low")
        check((try capturedBody()["reasoning"] as? [String: String])?["effort"] == "low", "MCP request uses the same reasoning contract")
        let fresh = OpenRouterStore(defaults: defaults, session: session)
        reset(data: catalog, delay: 0.1)
        let pending = Task { try await fresh.chat(messages: [], model: "vendor/reasoning", effort: "high") { _ in } }
        await awaitRequest()
        fresh.setAPIKey("")
        do { try await pending.value; fatalError("Revoked key must block completion after catalog discovery") }
        catch OpenRouterError.notConfigured { check(requestCount() == 1, "revoking the key during discovery sends no prompt") }
    }

    static func webSearchTransport() async throws {
        let suite = "spotter-search-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let store = OpenRouterStore(defaults: defaults, session: session)
        store.setAPIKey("fixture-key")
        let stream = Data("data: {\"choices\":[{\"delta\":{\"content\":\"Answer\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8)
        reset(data: stream)
        try await store.chat(messages: [("user", "fixture")], model: "vendor/plain") { _ in }
        check(try capturedBody()["plugins"] == nil, "a request without web search carries no search plugin")
        reset(data: stream)
        try await store.chat(messages: [("user", "fixture")], model: "vendor/plain", webSearch: true) { _ in }
        let plugins = try capturedBody()["plugins"] as? [[String: Any]]
        check(plugins?.first?["id"] as? String == "web" && plugins?.first?["max_results"] as? Int == 5,
            "web search adds OpenRouter's web plugin")
    }
}
